# Outputs for Nomad variables module

output "variables" {
  description = "Nomad variables information"
  value = {
    for k, v in nomad_variable.variables : k => {
      path      = v.path
      namespace = v.namespace
      items     = v.items
    }
  }
  sensitive = true
}

output "policies" {
  description = "Variable access policies"
  value = {
    read_policies = {
      for k, v in nomad_acl_policy.variable_read : k => {
        name = v.name
        id   = v.id
      }
    }
    write_policies = {
      for k, v in nomad_acl_policy.variable_write : k => {
        name = v.name
        id   = v.id
      }
    }
  }
}

output "tokens" {
  description = "Variable access tokens"
  value = {
    read_tokens = {
      for k, v in nomad_acl_token.variable_read_tokens : k => {
        name     = v.name
        accessor = v.accessor_id
      }
    }
    write_tokens = {
      for k, v in nomad_acl_token.variable_write_tokens : k => {
        name     = v.name
        accessor = v.accessor_id
      }
    }
  }
  sensitive = true
}