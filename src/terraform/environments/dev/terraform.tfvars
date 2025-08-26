# Development environment configuration

environment = "dev"
project_name = "vault-infrastructure"

# Vault configuration
vault_address = "https://vault-dev.service.consul:8200"
vault_skip_tls_verify = true

# Nomad configuration
nomad_address = "https://nomad-dev.service.consul:4646"

# Consul configuration
consul_address = "https://consul-dev.service.consul:8500"
consul_datacenter = "dc1"

# KV Engines for development
kv_engines = {
  "app-secrets-dev" = {
    description = "Development application secrets"
    max_versions = 3
    cas_required = false
  }
  "infrastructure-dev" = {
    description = "Development infrastructure secrets"
    max_versions = 5
    cas_required = false
  }
}

# AppRoles for development
approles = {
  "dev-services" = {
    token_ttl = 7200
    token_max_ttl = 14400
    token_policies = ["app-secrets-dev-write", "infrastructure-dev-read"]
    bind_secret_id = true
    secret_id_ttl = 86400
  }
}

# Development-specific Consul ACL policies
consul_acl_policies = {
  "dev-services" = {
    description = "Policy for development services"
    rules = <<EOT
service_prefix "" {
  policy = "write"
}

node_prefix "" {
  policy = "read"
}

key_prefix "dev/" {
  policy = "write"
}
EOT
  }
}

# Development Nomad variables
nomad_variables = {
  "dev-app-config" = {
    path = "nomad/jobs/dev/app/config"
    items = {
      "LOG_LEVEL" = "debug"
      "DEBUG_MODE" = "true"
      "MAX_CONNECTIONS" = "10"
    }
  }
}