# Developer policy - read/write access to specific paths

# KV v2 secrets - development namespace
path "secret/data/dev/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/dev/*" {
  capabilities = ["read", "list", "delete"]
}

# Database credentials - read only
path "database/creds/dev-*" {
  capabilities = ["read"]
}

# Transit encryption - development keys
path "transit/encrypt/dev-*" {
  capabilities = ["update"]
}

path "transit/decrypt/dev-*" {
  capabilities = ["update"]
}

path "transit/keys/dev-*" {
  capabilities = ["read", "list"]
}

# PKI - request certificates
path "pki/issue/dev-cert" {
  capabilities = ["create", "update"]
}

path "pki/certs" {
  capabilities = ["list"]
}

# Self-service token operations
path "auth/token/create" {
  capabilities = ["create", "update"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# Health check access
path "sys/health" {
  capabilities = ["read"]
}