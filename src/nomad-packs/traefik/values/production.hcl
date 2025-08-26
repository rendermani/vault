# Production Environment Values for Traefik Pack
# Optimized for high-availability production deployment

# Core Configuration
traefik_version = "v3.1"
environment     = "production"
region         = "global"
datacenter     = "dc1"
count          = 3

# Vault Integration
vault_integration      = true
vault_agent_enabled    = true
vault_address          = "https://vault.service.consul:8200"
vault_policies         = ["traefik-policy", "ssl-certificates"]
vault_role            = "traefik"

# SSL/ACME Configuration  
acme_enabled    = true
acme_email      = "ops@cloudya.net"
acme_ca_server  = "https://acme-v02.api.letsencrypt.org/directory"

acme_dns_challenge = {
  provider = "cloudflare"
  delay    = "60"
}

domains = [
  "vault.cloudya.net",
  "consul.cloudya.net",
  "nomad.cloudya.net", 
  "traefik.cloudya.net"
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

# Resource Allocation
resources = {
  cpu        = 1000
  memory     = 1024
  memory_max = 2048
}

vault_agent_resources = {
  cpu    = 200
  memory = 256
}

# Placement Constraints
constraints = [
  {
    attribute = "${attr.kernel.name}"
    operator  = "="
    value     = "linux"
  },
  {
    attribute = "${node.class}"
    operator  = "="
    value     = "system"
  }
]

spread = [
  {
    attribute = "${node.datacenter}"
    target    = "dc1"
    percent   = 100
  }
]

# Security Configuration
dashboard_enabled = true
dashboard_auth    = true
api_insecure      = false
debug_enabled     = false

tls_options = {
  min_version        = "VersionTLS12"
  cipher_suites     = [
    "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
    "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305",
    "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
    "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
    "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305",
    "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
  ]
  curve_preferences = [
    "CurveP521",
    "CurveP384", 
    "CurveP256"
  ]
  sni_strict        = true
}

middlewares = [
  "secure-headers@file",
  "rate-limit@file",
  "real-ip@file",
  "gzip@file"
]

# Logging Configuration
log_level = "INFO"

access_log = {
  enabled = true
  format  = "json"
  filters = {
    status_codes   = ["400-599"]
    retry_attempts = true
    min_duration   = "10ms"
  }
}

# Metrics Configuration
metrics = {
  prometheus = {
    enabled                = true
    buckets               = [0.1, 0.3, 1.2, 5.0, 10.0]
    add_entrypoints_labels = true
    add_services_labels    = true
    add_routers_labels     = true
  }
}

# Tracing (disabled in production by default)
tracing = {
  jaeger = {
    enabled         = false
    sampling_server = "http://jaeger.service.consul:5778/sampling"
    local_agent     = "jaeger.service.consul:6831"
    sampling_type   = "const"
    sampling_param  = 1.0
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

# Advanced Features
pilot_enabled = false