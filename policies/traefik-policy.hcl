# Traefik Service Policy
# Allows Traefik to access dashboard credentials and certificates

# Dashboard credentials access
path "secret/data/traefik/dashboard/*" {
  capabilities = ["read"]
}

path "secret/metadata/traefik/dashboard/*" {
  capabilities = ["read", "list"]
}

# Certificate management access
path "secret/data/traefik/certificates/*" {
  capabilities = ["read"]
}

path "secret/metadata/traefik/certificates/*" {
  capabilities = ["read", "list"]
}

# SSL/TLS certificate storage
path "secret/data/traefik/tls/*" {
  capabilities = ["read"]
}

path "secret/metadata/traefik/tls/*" {
  capabilities = ["read", "list"]
}

# Traefik configuration secrets
path "secret/data/traefik/config/*" {
  capabilities = ["read"]
}

path "secret/metadata/traefik/config/*" {
  capabilities = ["read", "list"]
}

# API keys and middleware secrets
path "secret/data/traefik/auth/*" {
  capabilities = ["read"]
}

path "secret/metadata/traefik/auth/*" {
  capabilities = ["read", "list"]
}

# Environment-specific paths
path "secret/data/traefik/environments/+/dashboard/*" {
  capabilities = ["read"]
}

path "secret/metadata/traefik/environments/+/dashboard/*" {
  capabilities = ["read", "list"]
}

path "secret/data/traefik/environments/+/certificates/*" {
  capabilities = ["read"]
}

path "secret/metadata/traefik/environments/+/certificates/*" {
  capabilities = ["read", "list"]
}

# Health check endpoints
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Allow token renewal for long-running services
path "sys/health" {
  capabilities = ["read"]
}