# Production Environment Policy
# Highly restricted access for production environment secrets

# Production environment secrets - read only
path "secret/data/environments/production/*" {
  capabilities = ["read"]
}

path "secret/metadata/environments/production/*" {
  capabilities = ["read", "list"]
}

# Production Traefik secrets - read only
path "secret/data/traefik/environments/production/*" {
  capabilities = ["read"]
}

path "secret/metadata/traefik/environments/production/*" {
  capabilities = ["read"]
}

# Production database credentials - read only
path "secret/data/database/production/*" {
  capabilities = ["read"]
}

# Production service configs - read only
path "secret/data/services/production/*" {
  capabilities = ["read"]
}

# Production certificates - read only (managed externally)
path "secret/data/certificates/production/*" {
  capabilities = ["read"]
}

# Production monitoring secrets
path "secret/data/monitoring/production/*" {
  capabilities = ["read"]
}

# Backup credentials for disaster recovery
path "secret/data/backup/production/*" {
  capabilities = ["read"]
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

# Emergency access logging
path "sys/audit-hash/*" {
  capabilities = ["create"]
}