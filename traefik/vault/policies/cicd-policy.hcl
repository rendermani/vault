# CI/CD Policy for GitHub Actions and automated deployment
path "secret/data/cicd/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/cicd/*" {
  capabilities = ["list", "read"]
}

# Traefik configuration secrets
path "secret/data/traefik/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/traefik/*" {
  capabilities = ["list", "read"]
}

# Database dynamic secrets
path "database/creds/app-role" {
  capabilities = ["read"]
}

path "database/creds/readonly-role" {
  capabilities = ["read"]
}

# PKI for certificates
path "pki/issue/server-cert" {
  capabilities = ["create", "update"]
}

path "pki/cert/ca" {
  capabilities = ["read"]
}

# Transit engine for encryption
path "transit/encrypt/app-key" {
  capabilities = ["create", "update"]
}

path "transit/decrypt/app-key" {
  capabilities = ["create", "update"]
}

# AWS dynamic secrets for CI/CD
path "aws/creds/deploy-role" {
  capabilities = ["read"]
}

# Azure dynamic secrets for CI/CD
path "azure/creds/deploy-role" {
  capabilities = ["read"]
}

# Read own token info
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

# List policies
path "sys/policies/acl" {
  capabilities = ["list"]
}

path "sys/policies/acl/cicd-policy" {
  capabilities = ["read"]
}