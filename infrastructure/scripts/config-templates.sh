#!/bin/bash
# Configuration templates for deployment scripts
# Source this file to get template generation functions

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Generate Consul configuration template
generate_consul_config() {
    local environment="$1"
    local datacenter="${2:-$DEFAULT_DATACENTER}"
    local data_dir="${3:-/opt/consul/data}"
    local config_dir="${4:-/etc/consul}"
    local log_dir="${5:-/var/log/consul}"
    local node_role="${6:-server}"
    local encrypt_key="$7"
    local bind_addr="${8:-0.0.0.0}"
    local client_addr="${9:-0.0.0.0}"
    local bootstrap_expect="${10:-1}"
    local ui_enabled="${11:-true}"
    
    local log_level
    case "$environment" in
        develop) log_level="DEBUG" ;;
        staging) log_level="INFO" ;;
        production) log_level="WARN" ;;
        *) log_level="INFO" ;;
    esac
    
    cat <<EOF
# Consul Configuration - $environment
datacenter = "$datacenter"
data_dir = "$data_dir"
log_level = "$log_level"
log_file = "$log_dir/consul.log"
log_rotate_duration = "24h"
log_rotate_max_files = 7
server = $([ "$node_role" = "server" ] && echo "true" || echo "false")

ui_config {
  enabled = $ui_enabled
}

bind_addr = "$bind_addr"
client_addr = "$client_addr"

connect {
  enabled = true
}

ports {
  grpc = 8502
}

encrypt = "$encrypt_key"

$(if [ "$node_role" = "server" ]; then
cat <<EOS

bootstrap_expect = $bootstrap_expect

# Performance settings
performance {
  raft_multiplier = 1
}

# Autopilot for server management
autopilot {
  cleanup_dead_servers = true
  last_contact_threshold = "200ms"
  max_trailing_logs = 250
  server_stabilization_time = "10s"
}
EOS
fi)

# Telemetry configuration
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname = true
}

$(if [ "$environment" = "production" ]; then
cat <<EOP

# TLS Configuration (production only)
# Uncomment and configure for production
# ca_file = "/etc/consul/tls/ca.pem"
# cert_file = "/etc/consul/tls/consul.pem"
# key_file = "/etc/consul/tls/consul-key.pem"
# verify_incoming = true
# verify_outgoing = true
# verify_server_hostname = true

# ACL Configuration (production only)
# Uncomment for production with proper ACL setup
# acl = {
#   enabled = true
#   default_policy = "deny"
#   enable_token_persistence = true
# }
EOP
fi)
EOF
}

# Generate Nomad configuration template
generate_nomad_config() {
    local environment="$1"
    local datacenter="${2:-$DEFAULT_DATACENTER}"
    local region="${3:-$DEFAULT_REGION}"
    local data_dir="${4:-/opt/nomad/data}"
    local plugin_dir="${5:-/opt/nomad/plugins}"
    local log_dir="${6:-/var/log/nomad}"
    local node_role="${7:-both}"  # server, client, or both
    local encrypt_key="$8"
    local bind_addr="${9:-0.0.0.0}"
    local advertise_addr="$10"
    local bootstrap_expect="${11:-1}"
    local consul_enabled="${12:-true}"
    local consul_address="${13:-127.0.0.1:8500}"
    local vault_enabled="${14:-false}"
    local vault_address="${15:-https://127.0.0.1:8200}"
    
    local log_level
    case "$environment" in
        develop) log_level="DEBUG" ;;
        staging) log_level="INFO" ;;
        production) log_level="WARN" ;;
        *) log_level="INFO" ;;
    esac
    
    # Auto-detect advertise address if not provided
    if [[ -z "$advertise_addr" ]]; then
        advertise_addr=$(ip route get 8.8.8.8 | awk '{print $7; exit}' 2>/dev/null || echo "127.0.0.1")
    fi
    
    cat <<EOF
# Nomad Configuration - $environment
datacenter = "$datacenter"
region = "$region"
data_dir = "$data_dir"
plugin_dir = "$plugin_dir"
log_level = "$log_level"
log_file = "$log_dir/nomad.log"
log_rotate_duration = "24h"
log_rotate_max_files = 7
enable_debug = false

bind_addr = "$bind_addr"
advertise {
  http = "$advertise_addr"
  rpc = "$advertise_addr"
  serf = "$advertise_addr"
}

ports {
  http = 4646
  rpc = 4647
  serf = 4648
}

$(if [[ "$node_role" == "server" || "$node_role" == "both" ]]; then
cat <<EOS

server {
  enabled = true
  bootstrap_expect = $bootstrap_expect
  encrypt = "$encrypt_key"
  
  # Server join configuration
  retry_join = ["127.0.0.1:4648"]
  
  # Performance tuning
  heartbeat_grace = "20s"
  min_heartbeat_ttl = "10s"
  max_heartbeats_per_second = 50
  
  # Enable event streaming for real-time updates
  event_buffer_size = 100
}
EOS
fi)

$(if [[ "$node_role" == "client" || "$node_role" == "both" ]]; then
cat <<EOC

client {
  enabled = true
  
  # Host volumes for bind mounts
  host_volume "docker-sock" {
    path = "/var/run/docker.sock"
    read_only = false
  }
  
  host_volume "host-tmp" {
    path = "/tmp"
    read_only = false
  }
  
  # Resource limits
  reserved {
    cpu = 100
    memory = 256
    disk = 1000
  }
  
  # Node metadata
  meta {
    node_type = "worker"
    environment = "$environment"
  }
  
  # Server join configuration
  servers = ["127.0.0.1:4647"]
}

# Docker plugin configuration
plugin "docker" {
  config {
    allow_privileged = $([ "$environment" = "develop" ] && echo "true" || echo "false")
    allow_caps = ["CHOWN", "DAC_OVERRIDE", "FSETID", "FOWNER", "MKNOD", "NET_RAW", "SETGID", "SETUID", "SETFCAP", "SETPCAP", "NET_BIND_SERVICE", "SYS_CHROOT", "KILL", "AUDIT_WRITE"]
    volumes {
      enabled = true
    }
    
    # Docker daemon configuration
    extra_labels = ["environment=$environment"]
    
    # Resource limits
    gc {
      image = true
      image_delay = "3m"
      container = true
      dangling_containers {
        enabled = true
        dry_run = false
        period = "5m"
        creation_grace = "5m"
      }
    }
  }
}
EOC
fi)

# UI configuration
ui {
  enabled = true
}

$(if [[ "$consul_enabled" == "true" ]]; then
cat <<EOCONSUL

consul {
  address = "$consul_address"
  auto_advertise = true
  server_auto_join = true
  client_auto_join = true
  
  # Service registration
  server_service_name = "nomad-server"
  client_service_name = "nomad-client"
  
  # Tags for service discovery
  tags = ["nomad", "$node_role", "$datacenter"]
  
  $(if [ "$environment" != "develop" ]; then
  cat <<EOTLS
  
  # TLS configuration for Consul communication
  # ca_file = "/etc/nomad/tls/consul-ca.pem"
  # cert_file = "/etc/nomad/tls/consul-client.pem"
  # key_file = "/etc/nomad/tls/consul-client-key.pem"
  # ssl = true
  # verify_ssl = true
EOTLS
  fi)
}
EOCONSUL
fi)

$(if [[ "$vault_enabled" == "true" ]]; then
cat <<EOVAULT

vault {
  enabled = true
  address = "$vault_address"
  
  # Vault integration settings
  create_from_role = "nomad-cluster"
  task_token_ttl = "1h"
  ca_path = "/opt/vault/tls/ca.crt"
  cert_path = "/opt/vault/tls/tls.crt"
  key_path = "/opt/vault/tls/tls.key"
  tls_server_name = "vault.service.consul"
}
EOVAULT
fi)

# Telemetry configuration
telemetry {
  collection_interval = "10s"
  disable_hostname = true
  prometheus_metrics = true
  publish_allocation_metrics = true
  publish_node_metrics = true
}

$(if [ "$environment" = "production" ]; then
cat <<EOPRODUCTION

# TLS configuration (production)
# Uncomment and configure for production
# tls {
#   http = true
#   rpc = true
#   ca_file = "/etc/nomad/tls/ca.crt"
#   cert_file = "/etc/nomad/tls/nomad.crt"
#   key_file = "/etc/nomad/tls/nomad.key"
#   verify_server_hostname = true
#   verify_https_client = true
# }

# ACL configuration (production)
# Uncomment for production with proper ACL tokens
# acl {
#   enabled = true
#   token_ttl = "30s"
#   policy_ttl = "60s"
# }
EOPRODUCTION
fi)
EOF
}

# Generate Vault configuration template
generate_vault_config() {
    local environment="$1"
    local data_dir="${2:-/vault/data}"
    local log_dir="${3:-/vault/logs}"
    local api_addr="$4"
    local cluster_addr="$5"
    local storage_backend="${6:-file}"
    local tls_cert_file="${7:-}"
    local tls_key_file="${8:-}"
    local tls_ca_file="${9:-}"
    
    local log_level ui_enabled tls_disable
    case "$environment" in
        develop) 
            log_level="DEBUG"
            ui_enabled="true"
            tls_disable="true"
            ;;
        staging) 
            log_level="INFO"
            ui_enabled="true"
            tls_disable="false"
            ;;
        production) 
            log_level="WARN"
            ui_enabled="true"
            tls_disable="false"
            ;;
        *) 
            log_level="INFO"
            ui_enabled="true"
            tls_disable="true"
            ;;
    esac
    
    cat <<EOF
# Vault Configuration - $environment
ui = $ui_enabled
disable_mlock = false
api_addr = "$api_addr"
cluster_addr = "$cluster_addr"

# Listener configuration
listener "tcp" {
  address       = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable   = $tls_disable
$(if [[ "$tls_disable" == "false" && -n "$tls_cert_file" ]]; then
cat <<EOTLS
  tls_cert_file = "$tls_cert_file"
  tls_key_file  = "$tls_key_file"
  tls_min_version = "tls12"
  tls_cipher_suites = "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
EOTLS
fi)
}

$(case "$storage_backend" in
  "file")
    cat <<EOSFILE
# File storage backend (development only)
storage "file" {
  path = "$data_dir"
}
EOSFILE
    ;;
  "consul")
    cat <<EOSCONSUL
# Consul storage backend for HA
storage "consul" {
  address = "consul.service.consul:8500"
  path    = "vault/"
  
  $(if [ "$environment" != "develop" ]; then
  cat <<EOCONSULTLS
  # Consul TLS configuration
  scheme = "https"
  tls_ca_file = "$tls_ca_file"
  tls_cert_file = "/vault/certs/consul-client.pem"
  tls_key_file = "/vault/certs/consul-client-key.pem"
  tls_skip_verify = false
EOCONSULTLS
  fi)
}
EOSCONSUL
    ;;
  *)
    echo "# Custom storage backend configuration required"
    ;;
esac)

$(if [ "$environment" = "production" ]; then
cat <<EOSEAL

# Auto-unseal with cloud KMS (production)
# Choose one of the following and configure appropriately:

# AWS KMS
# seal "awskms" {
#   region     = "us-west-2"
#   kms_key_id = "alias/vault-production-unseal"
# }

# Azure Key Vault
# seal "azurekeyvault" {
#   tenant_id      = "your-tenant-id"
#   client_id      = "your-client-id"
#   client_secret  = "your-client-secret"
#   vault_name     = "your-keyvault-name"
#   key_name       = "vault-unseal-key"
# }

# Google Cloud KMS
# seal "gcpckms" {
#   project    = "your-project-id"
#   region     = "us-central1"
#   key_ring   = "vault-keyring"
#   crypto_key = "vault-key"
# }
EOSEAL
fi)

# Telemetry configuration
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname = true
  
  # Enhanced metrics for production
  usage_gauge_period = "10m"
  maximum_gauge_cardinality = 500
  
  $(if [ "$environment" = "production" ]; then
  cat <<EOTELEMETRY
  
  # Production telemetry endpoints
  statsd_address = "localhost:8125"
  
  # Datadog integration (if used)
  # dogstatsd_addr = "localhost:8125"
  # dogstatsd_tags = ["environment:$environment", "service:vault"]
EOTELEMETRY
  fi)
}

# Log configuration
log_level = "$log_level"
log_format = "json"
log_file = "$log_dir/vault.log"
log_rotate_duration = "24h"
log_rotate_bytes = 104857600  # 100MB
log_rotate_max_files = $([ "$environment" = "production" ] && echo "30" || echo "7")

# Lease settings
default_lease_ttl = "$([ "$environment" = "production" ] && echo "168h" || echo "24h")"  # 7 days or 1 day
max_lease_ttl = "$([ "$environment" = "production" ] && echo "2160h" || echo "168h")"    # 90 days or 7 days

# Plugin directory
plugin_directory = "/vault/plugins"

# Cluster configuration
cluster_name = "vault-$environment"

# Performance settings
disable_clustering = false
$(if [ "$environment" = "production" ]; then
echo "disable_performance_standby = false"
echo "disable_sealwrap = false"
else
echo "disable_performance_standby = true"
echo "disable_sealwrap = true"
fi)

# API configuration
api_addr_environment_variable = "VAULT_API_ADDR"
cluster_addr_environment_variable = "VAULT_CLUSTER_ADDR"
EOF
}

# Generate Traefik configuration template (static config)
generate_traefik_static_config() {
    local environment="$1"
    local domain="${2:-$DEFAULT_DOMAIN}"
    local acme_email="$3"
    local lets_encrypt_staging="${4:-false}"
    local data_dir="${5:-/letsencrypt}"
    local config_dir="${6:-/config}"
    
    local log_level
    case "$environment" in
        develop) log_level="DEBUG" ;;
        staging) log_level="INFO" ;;
        production) log_level="WARN" ;;
        *) log_level="INFO" ;;
    esac
    
    local acme_server
    if [[ "$lets_encrypt_staging" == "true" ]]; then
        acme_server="https://acme-staging-v02.api.letsencrypt.org/directory"
    else
        acme_server="https://acme-v02.api.letsencrypt.org/directory"
    fi
    
    cat <<EOF
# Traefik Configuration - $environment
global:
  checkNewVersion: false
  sendAnonymousUsage: false

api:
  dashboard: true
  debug: $([ "$log_level" = "DEBUG" ] && echo "true" || echo "false")

log:
  level: $log_level
  format: json

accessLog:
  format: json
  fields:
    headers:
      defaultMode: keep
      names:
        User-Agent: redact
        Authorization: redact
        X-Forwarded-For: keep

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  
  websecure:
    address: ":443"
    http:
      tls:
        certResolver: letsencrypt
  
  metrics:
    address: ":8082"

certificatesResolvers:
  letsencrypt:
    acme:
      email: $acme_email
      storage: $data_dir/acme.json
      keyType: EC256
      caServer: $acme_server
      httpChallenge:
        entryPoint: web

providers:
  file:
    directory: $config_dir/dynamic
    watch: true

metrics:
  prometheus:
    addEntryPointsLabels: true
    addServicesLabels: true
    entryPoint: metrics

$(if [ "$environment" = "production" ]; then
cat <<EOPRODUCTION

# Production-specific settings
serversTransport:
  insecureSkipVerify: false
  rootCAs:
    - /etc/ssl/certs/ca-certificates.crt

# Rate limiting (if needed)
# experimental:
#   rateLimit:
#     average: 100
#     burst: 200
EOPRODUCTION
fi)
EOF
}

# Generate Traefik dynamic configuration template
generate_traefik_dynamic_config() {
    local environment="$1"
    local domain="${2:-$DEFAULT_DOMAIN}"
    local dashboard_auth="$3"
    
    cat <<EOF
# Traefik Dynamic Configuration - $environment
http:
  routers:
    dashboard:
      rule: "Host(\`traefik.$domain\`)"
      service: api@internal
      middlewares:
        - auth-dashboard
        - security-headers
      tls:
        certResolver: letsencrypt
    
    vault:
      rule: "Host(\`vault.$domain\`)"
      service: vault-service
      middlewares:
        - security-headers
      tls:
        certResolver: letsencrypt
    
    nomad:
      rule: "Host(\`nomad.$domain\`)"
      service: nomad-service
      middlewares:
        - security-headers
      tls:
        certResolver: letsencrypt

  services:
    vault-service:
      loadBalancer:
        servers:
          - url: "$([ "$environment" = "develop" ] && echo "http://localhost:8200" || echo "https://localhost:8220")"
    
    nomad-service:
      loadBalancer:
        servers:
          - url: "http://localhost:4646"

  middlewares:
    auth-dashboard:
      basicAuth:
        users:
          - "$dashboard_auth"
    
    security-headers:
      headers:
        frameDeny: true
        browserXssFilter: true
        contentTypeNosniff: true
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 63072000
        customRequestHeaders:
          X-Forwarded-Proto: "https"
        customResponseHeaders:
          X-Environment: "$environment"

tls:
  stores:
    default:
      defaultGeneratedCert:
        resolver: letsencrypt
        domain:
          main: "$domain"
          sans:
            - "*.$domain"
EOF
}

# Generate environment-specific job file template
generate_nomad_job_template() {
    local service="$1"
    local environment="$2"
    local namespace="${3:-default}"
    
    case "$service" in
        "vault")
            generate_vault_job_template "$environment" "$namespace"
            ;;
        "traefik")
            generate_traefik_job_template "$environment" "$namespace"
            ;;
        *)
            log_error "Unknown service: $service"
            return 1
            ;;
    esac
}

# Generate Vault job template
generate_vault_job_template() {
    local environment="$1"
    local namespace="${2:-default}"
    
    local job_name="vault-$environment"
    local count priority port_offset
    
    case "$environment" in
        develop)
            count=1
            priority=50
            port_offset=0
            ;;
        staging)
            count=1
            priority=100
            port_offset=10
            ;;
        production)
            count=3
            priority=200
            port_offset=20
            ;;
    esac
    
    cat <<EOF
job "$job_name" {
  namespace   = "$namespace"
  datacenters = ["dc1"]
  type        = "service"
  priority    = $priority

  update {
    max_parallel      = 1
    health_check      = "checks"
    min_healthy_time  = "120s"
    healthy_deadline  = "20m"
    progress_deadline = "30m"
    auto_revert       = true
    auto_promote      = $([ "$environment" = "develop" ] && echo "true" || echo "false")
    canary            = $([ "$environment" = "production" ] && echo "1" || echo "0")
  }

  group "vault" {
    count = $count

    volume "vault-data" {
      type      = "host"
      read_only = false
      source    = "vault-$environment-data"
    }

    volume "vault-config" {
      type      = "host"
      read_only = false
      source    = "vault-$environment-config"
    }

    volume "vault-logs" {
      type      = "host"
      read_only = false
      source    = "vault-$environment-logs"
    }

    $(if [ "$environment" != "develop" ]; then
    cat <<EOCERTS
    volume "vault-certs" {
      type      = "host"
      read_only = true
      source    = "vault-$environment-certs"
    }
EOCERTS
    fi)

    network {
      mode = "bridge"
      
      port "vault" {
        static = $((8200 + port_offset))
        to     = 8200
      }
      
      port "cluster" {
        static = $((8201 + port_offset))
        to     = 8201
      }
    }

    restart {
      attempts = 3
      interval = "10m"
      delay    = "60s"
      mode     = "delay"
    }

    $(if [ "$count" -gt 1 ]; then
    cat <<EOHA
    # High availability constraints
    constraint {
      attribute = "\${node.unique.name}"
      operator  = "distinct_hosts"
      value     = "true"
    }
EOHA
    fi)

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

      $(if [ "$environment" != "develop" ]; then
      cat <<EOCERTMOUNT
      volume_mount {
        volume      = "vault-certs"
        destination = "/vault/certs"
        read_only   = true
      }
EOCERTMOUNT
      fi)

      config {
        image = "hashicorp/vault:\${VAULT_VERSION}"
        ports = ["vault", "cluster"]
        
        volumes = [
          "local/config:/vault/config:ro"
        ]
        
        cap_add = ["IPC_LOCK"]
        
        command = "vault"
        args = ["server", "-config=/vault/config"]
      }

      # Vault configuration template will be inserted here
      template {
        destination = "local/config/vault.hcl"
        perms       = "644"
        change_mode = "restart"
        data        = <<EOF
# Configuration will be generated by deployment script
EOF
      }

      env {
        VAULT_ADDR = "$([ "$environment" = "develop" ] && echo "http://localhost:8200" || echo "https://localhost:8$((200 + port_offset))")"
        VAULT_API_ADDR = "$([ "$environment" = "develop" ] && echo "http://localhost:8200" || echo "https://vault.$DEFAULT_DOMAIN")"
        VAULT_CLUSTER_ADDR = "https://localhost:8$((201 + port_offset))"
        VAULT_LOG_LEVEL = "$([ "$environment" = "develop" ] && echo "DEBUG" || echo "INFO")"
        VAULT_LOG_FORMAT = "json"
        ENVIRONMENT = "$environment"
      }

      resources {
        cpu    = $([ "$environment" = "production" ] && echo "2000" || echo "1000")
        memory = $([ "$environment" = "production" ] && echo "2048" || echo "1024")
      }

      service {
        name = "vault-$environment"
        port = "vault"
        tags = ["vault", "$environment", "secrets"]
        
        check {
          type     = "http"
          path     = "/v1/sys/health?perfstandbyok=true"
          interval = "30s"
          timeout  = "10s"
          
          check_restart {
            limit = 3
            grace = "60s"
          }
        }
      }
    }
  }
}
EOF
}

# Generate Traefik job template
generate_traefik_job_template() {
    local environment="$1"
    local namespace="${2:-default}"
    
    cat <<EOF
job "traefik" {
  namespace   = "$namespace"
  datacenters = ["dc1"]
  type        = "service"
  priority    = 100

  update {
    max_parallel      = 1
    health_check      = "checks"
    min_healthy_time  = "30s"
    healthy_deadline  = "5m"
    progress_deadline = "10m"
    auto_revert       = true
    auto_promote      = false
    canary            = 0
  }

  group "traefik" {
    count = 1

    volume "traefik-certs" {
      type      = "host"
      read_only = false
      source    = "traefik-certs"
    }

    volume "traefik-config" {
      type      = "host"
      read_only = false
      source    = "traefik-config"
    }

    network {
      mode = "host"
      
      port "web" {
        static = 80
      }
      
      port "websecure" {
        static = 443
      }
      
      port "metrics" {
        static = 8082
      }
    }

    restart {
      attempts = 3
      interval = "5m"
      delay    = "30s"
      mode     = "delay"
    }

    task "traefik" {
      driver = "docker"
      
      volume_mount {
        volume      = "traefik-certs"
        destination = "/letsencrypt"
        read_only   = false
      }

      volume_mount {
        volume      = "traefik-config"
        destination = "/config"
        read_only   = false
      }

      config {
        image = "traefik:\${TRAEFIK_VERSION}"
        network_mode = "host"
        
        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock:ro"
        ]
      }

      # Traefik configuration will be managed by deployment script
      env {
        # Configuration via environment variables
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "traefik"
        port = "web"
        tags = ["traefik", "lb", "web"]
        
        check {
          type     = "http"
          port     = "web"
          path     = "/ping"
          interval = "10s"
          timeout  = "2s"
          
          check_restart {
            limit = 3
            grace = "90s"
          }
        }
      }
    }
  }
}
EOF
}

# Export template generation functions
export -f generate_consul_config generate_nomad_config generate_vault_config
export -f generate_traefik_static_config generate_traefik_dynamic_config
export -f generate_nomad_job_template generate_vault_job_template generate_traefik_job_template

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    log_info "Configuration templates loaded"
fi