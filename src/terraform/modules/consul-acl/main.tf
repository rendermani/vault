# Consul ACL Policies Module

terraform {
  required_providers {
    consul = {
      source  = "hashicorp/consul"
      version = "~> 2.20"
    }
  }
}

# Create ACL policies
resource "consul_acl_policy" "policies" {
  for_each = var.acl_policies

  name        = each.key
  description = each.value.description
  rules       = each.value.rules
}

# Create service-specific policies
resource "consul_acl_policy" "vault_service" {
  name        = "vault-service-${var.environment}"
  description = "Policy for Vault service registration and health checks"

  rules = <<-RULE
    service_prefix "vault" {
      policy = "write"
    }
    
    node_prefix "" {
      policy = "read"
    }
    
    key_prefix "vault/" {
      policy = "write"
    }
    
    session_prefix "" {
      policy = "write"
    }
    
    agent_prefix "" {
      policy = "read"
    }
  RULE
}

resource "consul_acl_policy" "nomad_service" {
  name        = "nomad-service-${var.environment}"
  description = "Policy for Nomad service registration and discovery"

  rules = <<-RULE
    service_prefix "nomad" {
      policy = "write"
    }
    
    service_prefix "" {
      policy = "read"
    }
    
    node_prefix "" {
      policy = "read"
    }
    
    key_prefix "nomad/" {
      policy = "write"
    }
    
    agent_prefix "" {
      policy = "read"
    }
  RULE
}

resource "consul_acl_policy" "applications" {
  name        = "applications-${var.environment}"
  description = "Policy for application services"

  rules = <<-RULE
    service_prefix "" {
      policy = "read"
    }
    
    node_prefix "" {
      policy = "read"
    }
    
    key_prefix "config/" {
      policy = "read"
    }
    
    key_prefix "applications/" {
      policy = "write"
    }
  RULE
}

# Create tokens for services
resource "consul_acl_token" "vault_token" {
  description = "Token for Vault service in ${var.environment}"
  policies    = [consul_acl_policy.vault_service.name]
  local       = false
}

resource "consul_acl_token" "nomad_token" {
  description = "Token for Nomad service in ${var.environment}"
  policies    = [consul_acl_policy.nomad_service.name]
  local       = false
}

resource "consul_acl_token" "applications_token" {
  description = "Token for applications in ${var.environment}"
  policies    = [consul_acl_policy.applications.name]
  local       = true
}

# Create role for automated token management
resource "consul_acl_role" "service_management" {
  name        = "service-management-${var.environment}"
  description = "Role for service token management"

  policies = [
    consul_acl_policy.vault_service.id,
    consul_acl_policy.nomad_service.id,
    consul_acl_policy.applications.id
  ]
}