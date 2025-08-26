# Vault KV v2 Secrets Engine Module

terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.20"
    }
  }
}

# Enable KV v2 secrets engines
resource "vault_mount" "kv" {
  for_each = var.kv_engines

  path        = each.key
  type        = "kv-v2"
  description = each.value.description

  options = {
    version = "2"
  }

  default_lease_ttl_seconds = each.value.default_lease_ttl_seconds
  max_lease_ttl_seconds     = each.value.max_lease_ttl_seconds

  tags = var.tags
}

# Configure KV v2 engines
resource "vault_kv_secret_backend_v2" "config" {
  for_each = var.kv_engines

  mount                = vault_mount.kv[each.key].path
  max_versions         = each.value.max_versions
  cas_required         = each.value.cas_required
  delete_version_after = each.value.delete_version_after

  depends_on = [vault_mount.kv]
}

# Create policies for KV access
resource "vault_policy" "kv_read" {
  for_each = var.kv_engines

  name = "${each.key}-read"

  policy = <<EOT
# Read access to ${each.key} KV store
path "${each.key}/data/*" {
  capabilities = ["read", "list"]
}

path "${each.key}/metadata/*" {
  capabilities = ["read", "list"]
}
EOT
}

resource "vault_policy" "kv_write" {
  for_each = var.kv_engines

  name = "${each.key}-write"

  policy = <<EOT
# Write access to ${each.key} KV store
path "${each.key}/data/*" {
  capabilities = ["create", "update", "read", "delete", "list"]
}

path "${each.key}/metadata/*" {
  capabilities = ["create", "update", "read", "delete", "list"]
}

path "${each.key}/config" {
  capabilities = ["read"]
}
EOT
}

resource "vault_policy" "kv_admin" {
  for_each = var.kv_engines

  name = "${each.key}-admin"

  policy = <<EOT
# Admin access to ${each.key} KV store
path "${each.key}/*" {
  capabilities = ["create", "update", "read", "delete", "list", "sudo"]
}
EOT
}