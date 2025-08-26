# Outputs for Consul ACL module

output "policies" {
  description = "ACL policies information"
  value = merge(
    {
      for k, v in consul_acl_policy.policies : k => {
        name = v.name
        id   = v.id
        description = v.description
      }
    },
    {
      vault_service = {
        name = consul_acl_policy.vault_service.name
        id   = consul_acl_policy.vault_service.id
        description = consul_acl_policy.vault_service.description
      }
      nomad_service = {
        name = consul_acl_policy.nomad_service.name
        id   = consul_acl_policy.nomad_service.id
        description = consul_acl_policy.nomad_service.description
      }
      applications = {
        name = consul_acl_policy.applications.name
        id   = consul_acl_policy.applications.id
        description = consul_acl_policy.applications.description
      }
    }
  )
}

output "tokens" {
  description = "ACL tokens information"
  value = {
    vault_token = {
      accessor = consul_acl_token.vault_token.accessor
      id       = consul_acl_token.vault_token.id
    }
    nomad_token = {
      accessor = consul_acl_token.nomad_token.accessor
      id       = consul_acl_token.nomad_token.id
    }
    applications_token = {
      accessor = consul_acl_token.applications_token.accessor
      id       = consul_acl_token.applications_token.id
    }
  }
  sensitive = true
}

output "roles" {
  description = "ACL roles information"
  value = {
    service_management = {
      name = consul_acl_role.service_management.name
      id   = consul_acl_role.service_management.id
      policies = consul_acl_role.service_management.policies
    }
  }
}