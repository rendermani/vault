# CI/CD pipeline policy - automated deployment access

# KV v2 secrets for CI/CD
path "secret/data/ci/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/ci/*" {
  capabilities = ["read", "list"]
}

# AppRole authentication for services
path "auth/approle/role/+/secret-id" {
  capabilities = ["create", "update"]
}

path "auth/approle/role/+/role-id" {
  capabilities = ["read"]
}

# Database credentials for deployments
path "database/creds/deployment-*" {
  capabilities = ["read"]
}

# PKI certificate issuance
path "pki/issue/deployment-cert" {
  capabilities = ["create", "update"]
}

path "pki/sign/deployment-cert" {
  capabilities = ["create", "update"]
}

# Transit encryption for secrets
path "transit/encrypt/deployment" {
  capabilities = ["update"]
}

path "transit/decrypt/deployment" {
  capabilities = ["update"]
}

path "transit/rewrap/deployment" {
  capabilities = ["update"]
}

# Token management for deployments
path "auth/token/create" {
  capabilities = ["create"]
  allowed_parameters = {
    "policies" = ["deployment-*"]
    "ttl" = []
    "max_ttl" = []
    "renewable" = ["true"]
  }
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# Health checks for deployment validation
path "sys/health" {
  capabilities = ["read"]
}

path "sys/seal-status" {
  capabilities = ["read"]
}