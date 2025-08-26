# Outputs for Nomad secrets engine module

output "backend_path" {
  description = "Nomad secrets engine backend path"
  value       = vault_nomad_secret_backend.nomad.backend
}

output "nomad_address" {
  description = "Nomad server address"
  value       = vault_nomad_secret_backend.nomad.address
}

output "roles" {
  description = "Nomad secret roles information"
  value = {
    management = {
      backend = vault_nomad_secret_role.management.backend
      role    = vault_nomad_secret_role.management.role
      type    = vault_nomad_secret_role.management.type
      policies = vault_nomad_secret_role.management.policies
    }
    client = {
      backend = vault_nomad_secret_role.client.backend
      role    = vault_nomad_secret_role.client.role
      type    = vault_nomad_secret_role.client.type
      policies = vault_nomad_secret_role.client.policies
    }
    server = {
      backend = vault_nomad_secret_role.server.backend
      role    = vault_nomad_secret_role.server.role
      type    = vault_nomad_secret_role.server.type
      policies = vault_nomad_secret_role.server.policies
    }
  }
}

output "policies" {
  description = "Nomad access policies"
  value = {
    admin = {
      name = vault_policy.nomad_admin.name
      id   = vault_policy.nomad_admin.id
    }
    operator = {
      name = vault_policy.nomad_operator.name
      id   = vault_policy.nomad_operator.id
    }
    client = {
      name = vault_policy.nomad_client.name
      id   = vault_policy.nomad_client.id
    }
  }
}