# Vault Agent Configuration for Traefik
# Handles automatic secret retrieval and template rendering

vault {
  address = "[[ .traefik.vault_address ]]"
  
  retry {
    num_retries = 5
    backoff {
      initial_interval = "5s"
      max_interval     = "30s"
      multiplier       = 2
    }
  }
}

# JWT Authentication using Nomad workload identity
auto_auth {
  method "jwt" {
    mount_path = "auth/jwt"
    config = {
      role = "[[ .traefik.vault_role ]]"
      path = "/secrets/token"
    }
  }

  sink "file" {
    config = {
      path = "/vault/secrets/.vault-token"
      mode = 0600
    }
  }
}

# Local listener for template processing
listener "unix" {
  address     = "/vault/secrets/agent.sock"
  tls_disable = true
  
  # Agent cache for improved performance
  cache {
    use_auto_auth_token = true
  }
}

# Enable persistent cache
cache {
  cache_dir = "/vault/cache"
  
  persist {
    type                = "kubernetes"
    path                = "/vault/cache/persistent"
    keep_after_import   = true
    exit_on_err         = true
  }
}

# Cloudflare API Key Template
template {
  source      = "/vault/config/cloudflare-key.tpl"
  destination = "/vault/secrets/cloudflare-key"
  perms       = 0600
  command     = "/bin/sh -c 'echo Cloudflare API key updated'"
  error_on_missing_key = true
  
  wait {
    min = "2s"
    max = "10s"
  }
}

# Cloudflare Email Template
template {
  source      = "/vault/config/cloudflare-email.tpl"
  destination = "/vault/secrets/cloudflare-email"
  perms       = 0600
  command     = "/bin/sh -c 'echo Cloudflare email updated'"
  error_on_missing_key = true
  
  wait {
    min = "2s"
    max = "10s"
  }
}

# Dashboard Authentication Template
[[ if and .traefik.dashboard_enabled .traefik.dashboard_auth ]]
template {
  source      = "/vault/config/dashboard-auth.tpl"
  destination = "/vault/secrets/dashboard-auth"
  perms       = 0600
  command     = "/bin/sh -c 'echo Dashboard auth updated'"
  error_on_missing_key = true
  
  wait {
    min = "2s"
    max = "10s"
  }
}
[[ end ]]

# TLS Certificate Template (if using Vault PKI)
template {
  source      = "/vault/config/tls-cert.tpl"
  destination = "/vault/secrets/tls-cert.pem"
  perms       = 0600
  command     = "/bin/sh -c 'echo TLS certificate updated'"
  error_on_missing_key = false
  
  wait {
    min = "2s"
    max = "10s"
  }
}

# TLS Private Key Template
template {
  source      = "/vault/config/tls-key.tpl"
  destination = "/vault/secrets/tls-key.pem"
  perms       = 0600
  command     = "/bin/sh -c 'echo TLS private key updated'"
  error_on_missing_key = false
  
  wait {
    min = "2s"
    max = "10s"
  }
}

# Consul ACL Token Template (for service discovery)
template {
  source      = "/vault/config/consul-token.tpl"
  destination = "/vault/secrets/consul-token"
  perms       = 0600
  command     = "/bin/sh -c 'echo Consul token updated'"
  error_on_missing_key = false
  
  wait {
    min = "2s"
    max = "10s"
  }
}

# Nomad ACL Token Template (for provider)
template {
  source      = "/vault/config/nomad-token.tpl"
  destination = "/vault/secrets/nomad-token"
  perms       = 0600
  command     = "/bin/sh -c 'echo Nomad token updated'"
  error_on_missing_key = false
  
  wait {
    min = "2s"
    max = "10s"
  }
}

# Monitoring credentials template
template {
  source      = "/vault/config/monitoring-config.tpl"
  destination = "/vault/secrets/monitoring-config.yml"
  perms       = 0600
  command     = "/bin/sh -c 'echo Monitoring config updated'"
  error_on_missing_key = false
  
  wait {
    min = "2s"
    max = "10s"
  }
}

# Dynamic middleware configuration
template {
  source      = "/vault/config/dynamic-middlewares.tpl"
  destination = "/vault/secrets/dynamic-middlewares.yml"
  perms       = 0644
  command     = "/bin/sh -c 'echo Dynamic middlewares updated'"
  error_on_missing_key = false
  
  wait {
    min = "2s"
    max = "10s"
  }
}

# Service discovery configuration
template {
  source      = "/vault/config/service-discovery.tpl"
  destination = "/vault/secrets/service-discovery.yml"
  perms       = 0644
  command     = "/bin/sh -c 'echo Service discovery config updated'"
  error_on_missing_key = false
  
  wait {
    min = "2s"
    max = "10s"
  }
}

# Exit after auth for initial setup
exit_after_auth = false

# Process supervisor integration
supervisor {
  enabled = true
}