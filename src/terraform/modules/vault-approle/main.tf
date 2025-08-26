# Vault AppRole Authentication Module

terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.20"
    }
  }
}

# Enable AppRole authentication
resource "vault_auth_backend" "approle" {
  type        = "approle"
  path        = "approle"
  description = "AppRole authentication backend for ${var.environment}"

  tune {
    max_lease_ttl      = "1h"
    default_lease_ttl  = "30m"
    token_type         = "default-service"
  }
}

# Create AppRoles
resource "vault_approle_auth_backend_role" "roles" {
  for_each = var.approles

  backend        = vault_auth_backend.approle.path
  role_name      = each.key
  token_ttl      = each.value.token_ttl
  token_max_ttl  = each.value.token_max_ttl
  token_policies = each.value.token_policies

  bind_secret_id    = each.value.bind_secret_id
  secret_id_ttl     = each.value.secret_id_ttl
  token_num_uses    = each.value.token_num_uses
  secret_id_num_uses = each.value.secret_id_num_uses

  # Security settings
  secret_id_bound_cidrs = ["127.0.0.1/32", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  token_bound_cidrs     = ["127.0.0.1/32", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

# Create Secret IDs for each AppRole
resource "vault_approle_auth_backend_role_secret_id" "secret_ids" {
  for_each = var.approles

  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.roles[each.key].role_name

  metadata = jsonencode({
    environment = var.environment
    created_by  = "terraform"
    role_name   = each.key
  })

  cidr_list = ["127.0.0.1/32", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

# Create policies for AppRole management
resource "vault_policy" "approle_admin" {
  name = "approle-admin-${var.environment}"

  policy = <<EOT
# AppRole administration
path "auth/approle/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# System mounts for AppRole backend
path "sys/auth/approle" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

path "sys/auth/approle/*" {
  capabilities = ["create", "read", "update", "delete"]
}
EOT
}

resource "vault_policy" "approle_operator" {
  name = "approle-operator-${var.environment}"

  policy = <<EOT
# AppRole operation
path "auth/approle/role/+/role-id" {
  capabilities = ["read"]
}

path "auth/approle/role/+/secret-id" {
  capabilities = ["create", "update"]
}

path "auth/approle/role/+/secret-id/lookup" {
  capabilities = ["create", "update"]
}

path "auth/approle/role/+/secret-id/destroy" {
  capabilities = ["create", "update"]
}
EOT
}