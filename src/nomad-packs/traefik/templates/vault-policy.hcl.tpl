# Vault Policy for Traefik - Phase 6 Production Ready
# Provides access to SSL certificates and configuration secrets

# DNS Challenge credentials for Let's Encrypt
path "kv/data/cloudflare" {
  capabilities = ["read"]
  description = "Read Cloudflare API credentials for DNS challenge"
}

# Dashboard authentication credentials
path "kv/data/traefik/dashboard" {
  capabilities = ["read"] 
  description = "Read Traefik dashboard authentication"
}

# SSL certificate storage (if using Vault for cert storage)
path "pki/issue/traefik" {
  capabilities = ["create", "update"]
  description = "Issue SSL certificates for Traefik"
}

# PKI certificate authority access
path "pki/ca/pem" {
  capabilities = ["read"]
  description = "Read CA certificate"
}

# Intermediate CA certificate access
path "pki/cert/ca" {
  capabilities = ["read"]
  description = "Read intermediate CA certificate"
}

# Traefik-specific configuration secrets
path "kv/data/traefik/config/*" {
  capabilities = ["read"]
  description = "Read Traefik configuration secrets"
}

# Service discovery credentials
path "kv/data/consul" {
  capabilities = ["read"]
  description = "Read Consul service discovery credentials"
}

path "kv/data/nomad" {
  capabilities = ["read"] 
  description = "Read Nomad service discovery credentials"
}

# Rate limiting and middleware configuration
path "kv/data/traefik/middlewares/*" {
  capabilities = ["read"]
  description = "Read middleware configurations"
}

# Monitoring and metrics credentials  
path "kv/data/monitoring/*" {
  capabilities = ["read"]
  description = "Read monitoring system credentials"
}

# Tracing system credentials (Jaeger, etc.)
path "kv/data/tracing/*" {
  capabilities = ["read"]
  description = "Read distributed tracing credentials"
}

# TLS certificate and key material
path "kv/data/tls/*" {
  capabilities = ["read"]
  description = "Read TLS certificates and keys"
}

# Service mesh certificates (Consul Connect)
path "connect/ca/roots" {
  capabilities = ["read"]
  description = "Read service mesh root certificates"
}

# Dynamic configuration updates
path "kv/data/traefik/dynamic/*" {
  capabilities = ["read"]
  description = "Read dynamic configuration updates"
}

# Database credentials for applications behind Traefik
path "database/creds/+" {
  capabilities = ["read"]
  description = "Read database credentials for proxied applications"
}

# JWT tokens for service authentication
path "auth/jwt/role/traefik" {
  capabilities = ["read"]
  description = "Read JWT role configuration"
}

# Token self-renewal capabilities
path "auth/token/renew-self" {
  capabilities = ["update"]
  description = "Renew own token"
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
  description = "Look up own token properties"
}

# Cubbyhole for temporary secrets
path "cubbyhole/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
  description = "Personal secret storage"
}