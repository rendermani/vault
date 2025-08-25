# Development Environment Policy
# Restricted access for development environment secrets

# Development environment secrets
path "secret/data/environments/develop/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/environments/develop/*" {
  capabilities = ["read", "list", "delete"]
}

# Development Traefik secrets
path "secret/data/traefik/environments/develop/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/traefik/environments/develop/*" {
  capabilities = ["read", "list"]
}

# Development database credentials
path "secret/data/database/develop/*" {
  capabilities = ["read"]
}

# Development service configs
path "secret/data/services/develop/*" {
  capabilities = ["read"]
}

# Development certificates (Let's Encrypt staging)
path "secret/data/certificates/develop/*" {
  capabilities = ["create", "read", "update", "delete"]
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