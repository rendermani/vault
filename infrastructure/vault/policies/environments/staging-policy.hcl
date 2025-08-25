# Staging Environment Policy
# Controlled access for staging environment secrets

# Staging environment secrets - read/list only
path "secret/data/environments/staging/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/environments/staging/*" {
  capabilities = ["read", "list"]
}

# Staging Traefik secrets
path "secret/data/traefik/environments/staging/*" {
  capabilities = ["read"]
}

path "secret/metadata/traefik/environments/staging/*" {
  capabilities = ["read", "list"]
}

# Staging database credentials - read only
path "secret/data/database/staging/*" {
  capabilities = ["read"]
}

# Staging service configs - read only
path "secret/data/services/staging/*" {
  capabilities = ["read"]
}

# Staging certificates (Let's Encrypt production)
path "secret/data/certificates/staging/*" {
  capabilities = ["read"]
}

# Configuration management - limited update for staging config
path "secret/data/config/staging/*" {
  capabilities = ["read", "update"]
}

# Token management
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Health monitoring
path "sys/health" {
  capabilities = ["read"]
}