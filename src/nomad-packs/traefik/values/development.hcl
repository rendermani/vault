# Development Environment Values for Traefik Pack
# Optimized for local development and testing

# Core Configuration
traefik_version = "v3.1"
environment     = "development"
region         = "global"
datacenter     = "dc1"
count          = 1

# Vault Integration
vault_integration      = true
vault_agent_enabled    = true
vault_address          = "http://vault.service.consul:8200"
vault_policies         = ["traefik-policy"]
vault_role            = "traefik"

# SSL/ACME Configuration (staging server for dev)
acme_enabled    = true
acme_email      = "dev@cloudya.net"
acme_ca_server  = "https://acme-staging-v02.api.letsencrypt.org/directory"

acme_dns_challenge = {
  provider = "cloudflare"
  delay    = "30"
}

domains = [
  "vault-dev.cloudya.net",
  "consul-dev.cloudya.net",
  "nomad-dev.cloudya.net",
  "traefik-dev.cloudya.net"
]

# Service Discovery
consul_integration      = true
consul_address         = "consul.service.consul:8500"
nomad_provider_enabled = true
nomad_address          = "nomad.service.consul:4646"

# Network Configuration
host_network = false  # Use bridge mode for dev

entrypoints = {
  web = {
    port            = 80
    redirect_to_tls = false  # Allow HTTP in dev
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

# Resource Allocation (minimal for dev)
resources = {
  cpu        = 200
  memory     = 256
  memory_max = 512
}

vault_agent_resources = {
  cpu    = 50
  memory = 64
}

# Placement Constraints (relaxed for dev)
constraints = [
  {
    attribute = "${attr.kernel.name}"
    operator  = "="
    value     = "linux"
  }
]

# Security Configuration (relaxed for dev)
dashboard_enabled = true
dashboard_auth    = false  # No auth in dev
api_insecure      = true   # Allow insecure API
debug_enabled     = true

tls_options = {
  min_version        = "VersionTLS12"
  cipher_suites     = [
    "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
    "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
  ]
  curve_preferences = [
    "CurveP256"
  ]
  sni_strict        = false
}

middlewares = [
  "secure-headers@file",
  "gzip@file"
]

# Logging Configuration (verbose for dev)
log_level = "DEBUG"

access_log = {
  enabled = true
  format  = "json"
  filters = {
    status_codes   = ["200-599"]  # Log all requests
    retry_attempts = true
    min_duration   = "1ms"
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

# Tracing (enabled for dev debugging)
tracing = {
  jaeger = {
    enabled         = true
    sampling_server = "http://jaeger.service.consul:5778/sampling"
    local_agent     = "jaeger.service.consul:6831"
    sampling_type   = "const"
    sampling_param  = 1.0
  }
}

# Health Checks (more frequent for dev)
health_checks = {
  http = {
    enabled      = true
    path         = "/ping"
    interval     = "5s"
    timeout      = "2s"
    grace_period = "3s"
  }
  tcp = {
    enabled  = true
    interval = "5s"
    timeout  = "2s"
  }
}

# Storage Configuration
storage = {
  acme_enabled = true
  volume_name  = "traefik-acme-dev"
  mount_path   = "/acme"
}

# Advanced Features
pilot_enabled = false