# Nomad Secrets Engine Module

terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.20"
    }
  }
}

# Enable Nomad secrets engine
resource "vault_nomad_secret_backend" "nomad" {
  backend                   = "nomad"
  description               = "Nomad secrets engine for ${var.environment}"
  default_lease_ttl_seconds = 1800
  max_lease_ttl_seconds     = 3600
  
  address                = var.nomad_address
  ca_cert                = var.nomad_ca_file != "" ? file(var.nomad_ca_file) : null
  client_cert            = var.nomad_cert_file != "" ? file(var.nomad_cert_file) : null
  client_key             = var.nomad_key_file != "" ? file(var.nomad_key_file) : null
  
  # Nomad token for Vault to use
  token                  = var.nomad_token
  
  # Connection settings
  max_token_name_length = 256
}

# Create Nomad roles for different access levels
resource "vault_nomad_secret_role" "management" {
  backend = vault_nomad_secret_backend.nomad.backend
  role    = "management"
  type    = "management"

  policies = ["management"]
  
  global = true
}

resource "vault_nomad_secret_role" "client" {
  backend = vault_nomad_secret_backend.nomad.backend
  role    = "client"
  type    = "client"

  policies = ["read-default", "submit-job"]
}

resource "vault_nomad_secret_role" "server" {
  backend = vault_nomad_secret_backend.nomad.backend
  role    = "server"
  type    = "management"

  policies = ["server-policy"]
  
  global = false
}

# Create policies for Nomad secrets access
resource "vault_policy" "nomad_admin" {
  name = "nomad-admin-${var.environment}"

  policy = <<EOT
# Admin access to Nomad secrets engine
path "nomad/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# System mounts for Nomad backend
path "sys/mounts/nomad" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

path "sys/mounts/nomad/*" {
  capabilities = ["create", "read", "update", "delete"]
}
EOT
}

resource "vault_policy" "nomad_operator" {
  name = "nomad-operator-${var.environment}"

  policy = <<EOT
# Operator access to Nomad secrets
path "nomad/creds/management" {
  capabilities = ["read"]
}

path "nomad/creds/client" {
  capabilities = ["read"]
}

path "nomad/creds/server" {
  capabilities = ["read"]
}

# List roles
path "nomad/roles" {
  capabilities = ["list"]
}

path "nomad/roles/*" {
  capabilities = ["read"]
}
EOT
}

resource "vault_policy" "nomad_client" {
  name = "nomad-client-${var.environment}"

  policy = <<EOT
# Client access to Nomad secrets
path "nomad/creds/client" {
  capabilities = ["read"]
}
EOT
}