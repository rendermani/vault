# Outputs for Vault AppRole module

output "approles" {
  description = "AppRole information"
  value = {
    for k, v in vault_approle_auth_backend_role.roles : k => {
      role_id      = v.role_id
      role_name    = v.role_name
      backend_path = v.backend
      token_policies = v.token_policies
      token_ttl    = v.token_ttl
      token_max_ttl = v.token_max_ttl
    }
  }
}

output "secret_ids" {
  description = "Secret IDs for AppRoles"
  value = {
    for k, v in vault_approle_auth_backend_role_secret_id.secret_ids : k => {
      secret_id = v.secret_id
      accessor  = v.accessor
    }
  }
  sensitive = true
}

output "backend_path" {
  description = "AppRole backend path"
  value       = vault_auth_backend.approle.path
}

output "policies" {
  description = "AppRole management policies"
  value = {
    admin = {
      name = vault_policy.approle_admin.name
      id   = vault_policy.approle_admin.id
    }
    operator = {
      name = vault_policy.approle_operator.name
      id   = vault_policy.approle_operator.id
    }
  }
}