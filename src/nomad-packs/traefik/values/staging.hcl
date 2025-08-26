# Staging Environment Values for Traefik Pack
# Production-like testing with staging ACME server

# Core Configuration
traefik_version = "v3.1"
environment     = "staging"
region         = "global"
datacenter     = "dc1"
count          = 2

# Vault Integration
vault_integration      = true
vault_agent_enabled    = true
vault_address          = "https://vault.service.consul:8200"
vault_policies         = ["traefik-policy"]
vault_role            = "traefik"

# SSL/ACME Configuration (using staging)
acme_enabled    = true
acme_email      = "ops@cloudya.net"
acme_ca_server  = "https://acme-staging-v02.api.letsencrypt.org/directory"

acme_dns_challenge = {
  provider = "cloudflare"
  delay    = "60"
}

domains = [
  "vault-staging.cloudya.net",
  "consul-staging.cloudya.net",
  "nomad-staging.cloudya.net",
  "traefik-staging.cloudya.net"
]

# Service Discovery
consul_integration      = true
consul_address         = "consul.service.consul:8500"
nomad_provider_enabled = true
nomad_address          = "nomad.service.consul:4646"

# Network Configuration
host_network = true

entrypoints = {
  web = {
    port            = 80
    redirect_to_tls = true
  }
  websecure = {
    port = 443
  }
  traefik = {
    port = 8080
  }
  metrics = {
    port = 8082
  }
}

# Resource Allocation (reduced for staging)
resources = {
  cpu        = 500
  memory     = 512
  memory_max = 1024
}

vault_agent_resources = {
  cpu    = 100
  memory = 128
}

# Security Configuration
dashboard_enabled = true
dashboard_auth    = true
api_insecure      = false
debug_enabled     = false

# Logging Configuration (more verbose)
log_level = "INFO"

access_log = {
  enabled = true
  format  = "json"
  filters = {
    status_codes   = ["300-599"]
    retry_attempts = true
    min_duration   = "5ms"
  }
}

# Metrics Configuration
metrics = {
  prometheus = {
    enabled                = true
    buckets               = [0.1, 0.3, 1.2, 5.0]
    add_entrypoints_labels = true
    add_services_labels    = true
    add_routers_labels     = true
  }
}

# Health Checks
health_checks = {
  http = {
    enabled      = true
    path         = "/ping"
    interval     = "10s"
    timeout      = "3s"
    grace_period = "5s"
  }
  tcp = {
    enabled  = true
    interval = "10s"
    timeout  = "3s"
  }
}

# Storage Configuration
storage = {
  acme_enabled = true
  volume_name  = "traefik-acme"
  mount_path   = "/acme"
}