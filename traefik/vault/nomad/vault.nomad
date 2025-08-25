job "vault" {
  datacenters = ["dc1"]
  type        = "service"
  priority    = 100

  update {
    max_parallel      = 1
    health_check      = "checks"
    min_healthy_time  = "30s"
    healthy_deadline  = "10m"
    progress_deadline = "15m"
    auto_revert       = true
    auto_promote      = true
    canary            = 0
  }

  group "vault" {
    count = 1

    # Persistent storage for Vault data
    volume "vault-data" {
      type      = "host"
      read_only = false
      source    = "vault-data"
    }

    volume "vault-config" {
      type      = "host"
      read_only = false
      source    = "vault-config"
    }

    volume "vault-logs" {
      type      = "host"
      read_only = false
      source    = "vault-logs"
    }

    network {
      mode = "bridge"
      
      port "vault" {
        static = 8200
        to     = 8200
      }
      
      port "cluster" {
        static = 8201
        to     = 8201
      }
    }

    restart {
      attempts = 5
      interval = "10m"
      delay    = "30s"
      mode     = "delay"
    }

    task "vault" {
      driver = "docker"
      
      volume_mount {
        volume      = "vault-data"
        destination = "/vault/data"
        read_only   = false
      }

      volume_mount {
        volume      = "vault-config"
        destination = "/vault/config"
        read_only   = false
      }

      volume_mount {
        volume      = "vault-logs"
        destination = "/vault/logs"
        read_only   = false
      }

      config {
        image = "hashicorp/vault:1.17.6"
        ports = ["vault", "cluster"]
        
        volumes = [
          "local/config:/vault/config:ro"
        ]
        
        cap_add = ["IPC_LOCK"]
        
        command = "vault"
        args = ["server", "-config=/vault/config"]
      }

      # Main Vault configuration
      template {
        destination = "local/config/vault.hcl"
        perms       = "644"
        change_mode = "restart"
        data        = <<EOF
# Vault Configuration
ui = true
disable_mlock = false
api_addr = "https://vault.cloudya.net"
cluster_addr = "http://{{ env "NOMAD_IP_cluster" }}:{{ env "NOMAD_PORT_cluster" }}"

# Listener configuration
listener "tcp" {
  address       = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable   = true  # TLS terminated at Traefik
}

# Storage backend - using file storage for simplicity
# In production, consider using Consul or database backend
storage "file" {
  path = "/vault/data"
}

# Telemetry
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname = true
}

# Log level
log_level = "INFO"
log_format = "json"

# Default lease settings
default_lease_ttl = "168h"
max_lease_ttl = "720h"

# Plugin directory
plugin_directory = "/vault/plugins"
EOF
      }

      # Initialize Vault script
      template {
        destination = "local/init-vault.sh"
        perms       = "755"
        data        = <<EOF
#!/bin/bash
set -e

export VAULT_ADDR="http://localhost:8200"

# Wait for Vault to be available
echo "Waiting for Vault to be available..."
timeout=300
while ! vault status >/dev/null 2>&1; do
  if [ $timeout -le 0 ]; then
    echo "Timeout waiting for Vault to be available"
    exit 1
  fi
  echo "Vault not ready, waiting..."
  sleep 5
  timeout=$((timeout-5))
done

# Check if Vault is already initialized
if vault status | grep -q "Initialized.*true"; then
  echo "Vault is already initialized"
  exit 0
fi

echo "Initializing Vault..."

# Initialize Vault with 5 key shares and threshold of 3
vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json > /vault/data/vault-init.json

echo "Vault initialized successfully!"
echo "IMPORTANT: The unseal keys and root token are stored in /vault/data/vault-init.json"
echo "Please secure these keys immediately!"

# Auto-unseal for development (remove in production)
UNSEAL_KEY_1=$(cat /vault/data/vault-init.json | jq -r '.unseal_keys_b64[0]')
UNSEAL_KEY_2=$(cat /vault/data/vault-init.json | jq -r '.unseal_keys_b64[1]')
UNSEAL_KEY_3=$(cat /vault/data/vault-init.json | jq -r '.unseal_keys_b64[2]')

vault operator unseal $UNSEAL_KEY_1
vault operator unseal $UNSEAL_KEY_2  
vault operator unseal $UNSEAL_KEY_3

echo "Vault unsealed successfully!"
EOF
      }

      # Environment variables
      env {
        VAULT_ADDR = "http://localhost:8200"
        VAULT_API_ADDR = "https://vault.cloudya.net"
        VAULT_CLUSTER_ADDR = "http://localhost:8201"
        VAULT_LOG_LEVEL = "INFO"
        VAULT_LOG_FORMAT = "json"
      }

      resources {
        cpu    = 1000
        memory = 1024
      }

      service {
        name = "vault"
        port = "vault"
        tags = ["vault", "secrets", "security"]
        
        check {
          type     = "http"
          path     = "/v1/sys/health"
          interval = "30s"
          timeout  = "5s"
          
          check_restart {
            limit = 3
            grace = "30s"
          }
        }
      }

      service {
        name = "vault-cluster"
        port = "cluster"
        tags = ["vault", "cluster"]
      }
    }

    # Initialization task
    task "init-storage" {
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      driver = "raw_exec"
      
      config {
        command = "/bin/bash"
        args    = ["-c", <<EOF
#!/bin/bash
set -e

echo "Initializing Vault persistent storage..."

# Create directories on host
mkdir -p /opt/nomad/volumes/vault-data
mkdir -p /opt/nomad/volumes/vault-config
mkdir -p /opt/nomad/volumes/vault-logs

# Set proper permissions
chmod 700 /opt/nomad/volumes/vault-data
chmod 755 /opt/nomad/volumes/vault-config
chmod 755 /opt/nomad/volumes/vault-logs

# Create initial directories inside vault-data
mkdir -p /opt/nomad/volumes/vault-data/core
mkdir -p /opt/nomad/volumes/vault-data/sys

echo "Vault storage initialization complete"
ls -la /opt/nomad/volumes/
EOF
        ]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}