# Vault Bootstrap Job for Phase 2
# Temporary deployment to avoid circular dependency

job "vault-bootstrap" {
  datacenters = ["dc1"]
  type        = "service"
  priority    = 90
  
  group "vault" {
    count = 3
    
    # Anti-affinity to spread across nodes
    constraint {
      operator  = "distinct_hosts"
      value     = "true"
    }
    
    # Prefer server nodes
    constraint {
      attribute = "${node.class}"
      value     = "server"
    }
    
    # Restart policy for bootstrap phase
    restart {
      attempts = 3
      interval = "5m"
      delay    = "25s"
      mode     = "delay"
    }
    
    # Update strategy
    update {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "30s"
      healthy_deadline = "5m"
      progress_deadline = "10m"
    }
    
    # Persistent storage for Vault data
    volume "vault-data" {
      type      = "host"
      source    = "vault-data"
      read_only = false
    }
    
    network {
      port "vault_ui" {
        static = 8200
      }
      port "vault_cluster" {
        static = 8201
      }
    }
    
    service {
      name = "vault"
      port = "vault_ui"
      
      tags = [
        "vault",
        "bootstrap",
        "ui",
        "traefik.enable=true",
        "traefik.http.routers.vault.rule=Host(`vault.service.consul`)",
        "traefik.http.routers.vault.tls=true"
      ]
      
      check {
        name     = "Vault HTTP"
        type     = "http"
        path     = "/v1/sys/health?standbyok=true"
        interval = "30s"
        timeout  = "5s"
        
        check_restart {
          limit           = 3
          grace           = "10s"
          ignore_warnings = false
        }
      }
      
      check {
        name     = "Vault TCP"
        type     = "tcp"
        interval = "30s"
        timeout  = "5s"
      }
    }
    
    task "vault" {
      driver = "docker"
      
      config {
        image = "hashicorp/vault:1.15.2"
        
        ports = ["vault_ui", "vault_cluster"]
        
        args = [
          "vault", "server", 
          "-config=/local/vault.hcl"
        ]
        
        volumes = [
          "local/vault.hcl:/local/vault.hcl",
        ]
        
        cap_add = ["IPC_LOCK"]
      }
      
      # Mount persistent storage
      volume_mount {
        volume      = "vault-data"
        destination = "/vault/data"
        read_only   = false
      }
      
      # Environment variables
      env {
        VAULT_LOCAL_CONFIG = "true"
        VAULT_LOG_LEVEL    = "INFO"
        VAULT_CLUSTER_ADDR = "https://${NOMAD_IP_vault_cluster}:8201"
      }
      
      # Vault configuration template
      template {
        data = <<EOF
# Vault Bootstrap Configuration
# Based on proven patterns from /config/vault.hcl

ui = true
log_level = "INFO"
log_format = "json"

# API listener
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = false
  
  # Temporary self-signed certificates for bootstrap
  tls_cert_file = "/local/vault.crt"  
  tls_key_file  = "/local/vault.key"
  tls_min_version = "tls12"
}

# Cluster listener
listener "tcp" {
  address         = "0.0.0.0:8201"
  purpose         = "cluster"
  tls_disable     = false
  tls_cert_file   = "/local/vault.crt"
  tls_key_file    = "/local/vault.key"
}

# Storage backend (Consul)
storage "consul" {
  address = "consul.service.consul:8500"
  path    = "vault/"
  
  # Service registration
  service = "vault"
  service_tags = "vault,bootstrap"
  
  # Session TTL
  session_ttl = "15s"
  lock_wait_time = "25s"
}

# Cluster configuration
cluster_addr = "https://{{ env "NOMAD_IP_vault_cluster" }}:8201"
api_addr     = "https://{{ env "NOMAD_IP_vault_ui" }}:8200"

# Performance and limits
default_lease_ttl = "768h"
max_lease_ttl     = "8760h"

# Plugin directory
plugin_directory = "/vault/plugins"

# Raw storage endpoint (disabled for security)
raw_storage_endpoint = false

# Disable performance standby for bootstrap
disable_performance_standby = true

# Telemetry
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname = true
}

# Audit logging (file)
# audit {
#   type = "file"
#   options {
#     file_path = "/vault/logs/audit.log"
#   }
# }
EOF
        destination = "local/vault.hcl"
        change_mode = "restart"
      }
      
      # Generate temporary TLS certificates
      template {
        data = <<EOF
{{ key "vault/bootstrap/tls/cert" }}
EOF
        destination = "local/vault.crt"
        change_mode = "restart"
      }
      
      template {  
        data = <<EOF
{{ key "vault/bootstrap/tls/key" }}
EOF
        destination = "local/vault.key"
        change_mode = "restart"
        perms       = "600"
      }
      
      # Resource limits
      resources {
        cpu    = 1000  # 1 CPU
        memory = 1024  # 1GB RAM
      }
      
      # Graceful shutdown
      kill_timeout = "30s"
      kill_signal  = "SIGTERM"
    }
  }
}