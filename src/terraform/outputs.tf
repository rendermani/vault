# Outputs for Vault infrastructure

# KV Engines
output "kv_engines" {
  description = "KV v2 engines information"
  value = {
    for k, v in module.vault_kv.kv_engines : k => {
      path        = v.path
      description = v.description
      max_versions = v.max_versions
    }
  }
}

# AppRoles
output "approles" {
  description = "AppRole authentication information"
  value = {
    for k, v in module.vault_approle.approles : k => {
      role_id = v.role_id
      path    = v.backend_path
      policies = v.token_policies
    }
  }
  sensitive = true
}

# Nomad secrets engine
output "nomad_secrets_engine" {
  description = "Nomad secrets engine information"
  value = {
    backend = module.nomad_secrets.backend_path
    address = module.nomad_secrets.nomad_address
  }
}

# Consul ACL policies
output "consul_acl_policies" {
  description = "Consul ACL policies information"
  value = {
    for k, v in module.consul_acl.policies : k => {
      name = v.name
      id   = v.id
    }
  }
}

# Nomad variables
output "nomad_variables" {
  description = "Nomad variables information"
  value = {
    for k, v in module.nomad_variables.variables : k => {
      path      = v.path
      namespace = v.namespace
      keys      = keys(v.items)
    }
  }
  sensitive = true
}

# Summary
output "infrastructure_summary" {
  description = "Summary of deployed infrastructure"
  value = {
    environment = var.environment
    kv_engines_count = length(module.vault_kv.kv_engines)
    approles_count = length(module.vault_approle.approles)
    consul_policies_count = length(module.consul_acl.policies)
    nomad_variables_count = length(module.nomad_variables.variables)
    deployment_timestamp = timestamp()
  }
}