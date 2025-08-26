# Outputs for Vault KV v2 module

output "kv_engines" {
  description = "KV v2 engines information"
  value = {
    for k, v in vault_mount.kv : k => {
      path         = v.path
      type         = v.type
      description  = v.description
      accessor     = v.accessor
      max_versions = vault_kv_secret_backend_v2.config[k].max_versions
    }
  }
}

output "kv_policies" {
  description = "KV policies information"
  value = {
    read_policies = {
      for k, v in vault_policy.kv_read : k => {
        name = v.name
        id   = v.id
      }
    }
    write_policies = {
      for k, v in vault_policy.kv_write : k => {
        name = v.name
        id   = v.id
      }
    }
    admin_policies = {
      for k, v in vault_policy.kv_admin : k => {
        name = v.name
        id   = v.id
      }
    }
  }
}