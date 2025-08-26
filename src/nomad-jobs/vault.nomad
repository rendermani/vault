job "vault" {
  datacenters = ["dc1"]
  type        = "service"
  priority    = 90

  group "vault" {
    count = 3

    # Volume for persistent storage
    volume "vault-data" {
      type      = "host"
      source    = "vault-data"
      read_only = false
    }

    network {
      port "http" {
        static = 8200
      }
      port "cluster" {
        static = 8201
      }
    }

    # Restart policy for high availability
    restart {
      attempts = 3
      interval = "10m"
      delay    = "30s"
      mode     = "fail"
    }

    # Update strategy for rolling deployments
    update {
      max_parallel      = 1
      min_healthy_time  = "30s"
      healthy_deadline  = "3m"
      progress_deadline = "10m"
      canary           = 1
      auto_revert      = true
      auto_promote     = true
    }

    task "vault" {
      driver = "docker"

      # Mount the persistent volume
      volume_mount {
        volume      = "vault-data"
        destination = "/vault/data"
        read_only   = false
      }

      config {
        image = "hashicorp/vault:1.15.4"
        ports = ["http", "cluster"]

        # Vault configuration
        args = [
          "vault",
          "server",
          "-config=/vault/config/vault.hcl"
        ]

        # Security: run as non-root user
        user = "100:1000"

        # Capabilities for mlock
        cap_add = ["IPC_LOCK"]
      }

      # Vault configuration file
      template {
        data = <<EOF
# Vault Configuration - Phase 2 (Nomad Deployment)
ui = true

# Storage backend - Raft for Phase 2
storage "raft" {
  path    = "/vault/data"
  node_id = "{{ env "NOMAD_ALLOC_ID" }}"
  
  retry_join {
    leader_api_addr = "http://{{ env "NOMAD_IP_http" }}:8200"
  }
}

# Cluster configuration
cluster_addr = "http://{{ env "NOMAD_IP_cluster" }}:8201"
api_addr     = "http://{{ env "NOMAD_IP_http" }}:8200"

# Security: Bind to localhost only (will use Consul Connect later)
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = true
  
  # Disable clustering listener on public interface
  cluster_address = "{{ env "NOMAD_IP_cluster" }}:8201"
}

# Disable mlock for containerized environments
disable_mlock = true

# Logging
log_level = "INFO"
log_format = "json"

# Telemetry
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname = true
}

# Maximum request duration
max_request_duration = "90s"

# Default lease settings
default_lease_ttl = "168h"
max_lease_ttl = "720h"

# Plugin directory
plugin_directory = "/vault/plugins"

# Seal configuration (auto-unseal will be configured in Phase 4)
seal "shamir" {
  # Default Shamir seal for Phase 2
}
EOF

        destination = "/vault/config/vault.hcl"
        change_mode = "restart"
        perms       = "644"
      }

      # Environment variables
      env {
        VAULT_ADDR = "http://127.0.0.1:8200"
        VAULT_API_ADDR = "http://{{ env "NOMAD_IP_http" }}:8200"
        VAULT_CLUSTER_ADDR = "http://{{ env "NOMAD_IP_cluster" }}:8201"
        VAULT_LOG_LEVEL = "INFO"
        VAULT_LOG_FORMAT = "json"
        SKIP_CHOWN = "true"
        SKIP_SETCAP = "true"
      }

      # Resource allocation
      resources {
        cpu    = 1000  # 1 CPU core
        memory = 2048  # 2GB RAM
      }

      # Health checks
      service {
        name = "vault"
        port = "http"
        tags = [
          "vault",
          "secret-management",
          "phase-2",
          "raft-storage"
        ]

        # Health check configuration
        check {
          name     = "Vault Health Check"
          type     = "http"
          path     = "/v1/sys/health"
          interval = "10s"
          timeout  = "5s"
          
          # Vault returns 200 for initialized+unsealed, 501 for uninitialized, 503 for sealed
          check_restart {
            limit = 3
            grace = "30s"
            ignore_warnings = false
          }
        }

        # Leader check
        check {
          name     = "Vault Leader Check"
          type     = "http"
          path     = "/v1/sys/leader"
          interval = "30s"
          timeout  = "5s"
        }

        # Ready check (stricter than health)
        check {
          name     = "Vault Ready Check"
          type     = "http"
          path     = "/v1/sys/health?standbyok=true&sealedcode=200&uninitcode=200"
          interval = "15s"
          timeout  = "5s"
        }

        # Connect for service mesh (prepared for Phase 4)
        connect {
          sidecar_service {
            tags = ["vault-sidecar"]
            
            proxy {
              upstreams {
                destination_name = "consul"
                local_bind_port  = 8500
              }
            }
          }
        }
      }

      # Service for cluster communication
      service {
        name = "vault-cluster"
        port = "cluster"
        tags = [
          "vault-cluster",
          "raft-peer"
        ]

        check {
          name     = "Vault Cluster Port"
          type     = "tcp"
          interval = "15s"
          timeout  = "3s"
        }
      }

      # Kill timeout for graceful shutdown
      kill_timeout = "30s"

      # Shutdown delay for leader election
      shutdown_delay = "5s"

      # Constraint: Spread across different nodes for HA
      constraint {
        distinct_hosts = true
      }

      # Vault initialization script (runs once)
      template {
        data = <<EOF
#!/bin/bash
# Vault Phase 2 Initialization Script

set -e

# Wait for Vault to be ready
echo "Waiting for Vault to start..."
until curl -f http://localhost:8200/v1/sys/health; do
  echo "Vault not ready yet, waiting 5 seconds..."
  sleep 5
done

# Check if already initialized
if curl -s http://localhost:8200/v1/sys/init | jq -r '.initialized' | grep -q true; then
  echo "Vault is already initialized"
  exit 0
fi

# Initialize Vault (only on first node)
if [ "{{ env "NOMAD_ALLOC_INDEX" }}" = "0" ]; then
  echo "Initializing Vault..."
  
  # Initialize with 5 key shares, 3 required for unsealing
  INIT_RESPONSE=$(curl -s \
    --request POST \
    --data '{"secret_shares": 5, "secret_threshold": 3}' \
    http://localhost:8200/v1/sys/init)
  
  # Store keys securely (in production, use external key management)
  echo "$INIT_RESPONSE" > /vault/data/vault-init.json
  chmod 600 /vault/data/vault-init.json
  
  echo "Vault initialized successfully"
  
  # Extract unseal keys and root token
  UNSEAL_KEYS=$(echo "$INIT_RESPONSE" | jq -r '.keys[]')
  ROOT_TOKEN=$(echo "$INIT_RESPONSE" | jq -r '.root_token')
  
  # Unseal Vault
  echo "Unsealing Vault..."
  for key in $(echo "$INIT_RESPONSE" | jq -r '.keys[0:3][]'); do
    curl -s \
      --request POST \
      --data "{\"key\": \"$key\"}" \
      http://localhost:8200/v1/sys/unseal
  done
  
  echo "Vault unsealed successfully"
  
  # Enable audit logging
  curl -s \
    --header "X-Vault-Token: $ROOT_TOKEN" \
    --request POST \
    --data '{"type": "file", "options": {"file_path": "/vault/logs/audit.log"}}' \
    http://localhost:8200/v1/sys/audit/file
  
  echo "Audit logging enabled"
  
fi
EOF

        destination = "/local/vault-init.sh"
        change_mode = "noop"
        perms       = "755"
      }

      # Post-start script for configuration
      lifecycle {
        hook    = "poststart"
        sidecar = false
      }
    }

    # Constraint: Ensure we have the vault-data volume
    constraint {
      attribute = "${node.class}"
      value     = "vault"
    }

    # Affinity: Prefer nodes with SSD storage
    affinity {
      attribute = "${meta.storage_type}"
      value     = "ssd"
      weight    = 50
    }
  }
}