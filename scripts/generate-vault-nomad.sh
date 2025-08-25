#!/bin/bash
set -euo pipefail

# Script to generate vault.nomad files for all environments
# This fixes the YAML heredoc syntax issue in GitHub Actions

echo "Generating vault.nomad files for all environments..."

# Create directories
mkdir -p infrastructure/nomad/jobs/{production,staging,develop}

# Generate production vault.nomad
cat > infrastructure/nomad/jobs/production/vault.nomad << 'EOF'
job "vault-production" {
  datacenters = ["dc1", "dc2", "dc3"]
  type        = "service"
  priority    = 200

  update {
    max_parallel      = 1
    health_check      = "checks"
    min_healthy_time  = "120s"
    healthy_deadline  = "20m"
    progress_deadline = "30m"
    auto_revert       = true
    auto_promote      = false
    canary            = 1
  }

  group "vault" {
    count = 3

    volume "vault-data" {
      type      = "host"
      read_only = false
      source    = "vault-production-data"
    }

    volume "vault-config" {
      type      = "host"
      read_only = false
      source    = "vault-production-config"
    }

    volume "vault-logs" {
      type      = "host"
      read_only = false
      source    = "vault-production-logs"
    }

    volume "vault-certs" {
      type      = "host"
      read_only = true
      source    = "vault-production-certs"
    }

    volume "vault-backup" {
      type      = "host"
      read_only = false
      source    = "vault-production-backup"
    }

    network {
      port "vault-http" {
        static = 8200
        to     = 8200
      }
      port "vault-cluster" {
        static = 8201
        to     = 8201
      }
    }

    restart {
      attempts = 2
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    ephemeral_disk {
      size = 500
    }

    task "vault" {
      driver = "docker"

      config {
        image = "hashicorp/vault:1.15.4"
        ports = ["vault-http", "vault-cluster"]
        
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

        volume_mount {
          volume      = "vault-certs"
          destination = "/vault/certs"
          read_only   = true
        }

        volume_mount {
          volume      = "vault-backup"
          destination = "/vault/backup"
          read_only   = false
        }

        command = "vault"
        args    = ["server", "-config=/vault/config"]
        
        cap_add = ["IPC_LOCK"]
      }

      env {
        VAULT_LOCAL_CONFIG = jsonencode({
          storage = {
            consul = {
              address = "127.0.0.1:8500"
              path    = "vault/production/"
            }
          }
          listener = {
            tcp = {
              address = "0.0.0.0:8200"
              tls_disable = false
              tls_cert_file = "/vault/certs/vault.crt"
              tls_key_file = "/vault/certs/vault.key"
            }
          }
          ui = true
          api_addr = "https://vault.cloudya.net:8220"
          cluster_addr = "https://vault.cloudya.net:8221"
          disable_mlock = false
          log_level = "INFO"
          log_format = "json"
        })
      }

      resources {
        cpu    = 2000
        memory = 4096
      }

      service {
        name = "vault-production"
        port = "vault-http"
        
        tags = [
          "vault",
          "production",
          "traefik.enable=true",
          "traefik.http.routers.vault-production.rule=Host(\`vault.cloudya.net\`)",
          "traefik.http.routers.vault-production.tls=true",
          "traefik.http.routers.vault-production.tls.certresolver=letsencrypt",
          "traefik.http.services.vault-production.loadbalancer.server.port=8200"
        ]

        check {
          name     = "Vault Health"
          type     = "http"
          path     = "/v1/sys/health"
          interval = "30s"
          timeout  = "10s"
          check_restart {
            limit = 3
            grace = "90s"
            ignore_warnings = false
          }
        }
      }
    }
  }
}
EOF

# Generate develop vault.nomad (single instance)
sed 's/vault-production/vault-develop/g; s/production/develop/g; s/dc1", "dc2", "dc3/dc1/g; s/count = 3/count = 1/g' \
  infrastructure/nomad/jobs/production/vault.nomad > infrastructure/nomad/jobs/develop/vault.nomad

# Generate staging vault.nomad (2 instances)
sed 's/vault-production/vault-staging/g; s/production/staging/g; s/dc1", "dc2", "dc3/dc1/g; s/count = 3/count = 2/g' \
  infrastructure/nomad/jobs/production/vault.nomad > infrastructure/nomad/jobs/staging/vault.nomad

echo "✅ Successfully generated vault.nomad files for all environments:"
echo "  - infrastructure/nomad/jobs/production/vault.nomad (3 instances)"
echo "  - infrastructure/nomad/jobs/staging/vault.nomad (2 instances)"
echo "  - infrastructure/nomad/jobs/develop/vault.nomad (1 instance)"

# Verify files were created
for env in production staging develop; do
  if [[ -f "infrastructure/nomad/jobs/${env}/vault.nomad" ]]; then
    echo "✅ ${env}/vault.nomad: $(wc -l < "infrastructure/nomad/jobs/${env}/vault.nomad") lines"
  else
    echo "❌ ${env}/vault.nomad: MISSING"
    exit 1
  fi
done