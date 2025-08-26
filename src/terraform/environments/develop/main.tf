# Development Environment Terraform Configuration
terraform {
  required_version = ">= 1.6"
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.20"
    }
    nomad = {
      source  = "hashicorp/nomad"
      version = "~> 2.0"
    }
    consul = {
      source  = "hashicorp/consul"
      version = "~> 2.20"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
  
  backend "consul" {
    address = "cloudya.net:8500"
    scheme  = "http"
    path    = "terraform/state/develop/vault-infrastructure"
    gzip    = true
  }
}

# Development environment providers with relaxed security
provider "vault" {
  address         = var.vault_address
  skip_tls_verify = true
  # Token provided via environment variable VAULT_TOKEN
}

provider "nomad" {
  address = var.nomad_address
  region  = "global"
}

provider "consul" {
  address    = var.consul_address
  datacenter = "dc1"
}

# Local values for development
locals {
  environment = "develop"
  server_ip   = split(":", var.consul_address)[0]
  
  common_tags = {
    Environment = "develop"
    ManagedBy   = "terraform"
    Project     = "vault-infrastructure"
    SecurityLevel = "relaxed"
  }
}

# Development Vault KV engines
resource "vault_mount" "app_secrets_dev" {
  path        = "app-secrets-dev"
  type        = "kv-v2"
  description = "Application secrets for development environment"

  options = {
    version = "2"
  }
}

resource "vault_mount" "infrastructure_dev" {
  path        = "infrastructure-dev"
  type        = "kv-v2"
  description = "Infrastructure secrets for development environment"

  options = {
    version = "2"
  }
}

# Development AppRole for Nomad
resource "vault_auth_backend" "approle_dev" {
  type = "approle"
  path = "approle-dev"
}

resource "vault_approle_auth_backend_role" "nomad_dev" {
  backend        = vault_auth_backend.approle_dev.path
  role_name      = "nomad-dev"
  token_policies = ["nomad-policy-dev"]
  
  # Relaxed settings for development
  token_ttl      = 3600
  token_max_ttl  = 7200
  bind_secret_id = true
  secret_id_ttl  = 86400
}

# Development policy for Nomad
resource "vault_policy" "nomad_dev" {
  name = "nomad-policy-dev"

  policy = <<EOT
# Development Nomad policy - relaxed permissions
path "app-secrets-dev/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "infrastructure-dev/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Allow Nomad to manage its own secrets
path "secret/nomad/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Allow reading auth methods
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOT
}

# Environment configuration file
resource "local_file" "environment_config" {
  content = templatefile("${path.root}/../../templates/environment.tpl", {
    environment = local.environment
    server_ip   = local.server_ip
    timestamp   = timestamp()
    vault_addr  = var.vault_address
    nomad_addr  = var.nomad_address
    consul_addr = var.consul_address
    security_level = "relaxed"
  })
  filename = "${path.module}/generated/environment-develop.yaml"
}

# Development-specific Nomad variables
resource "nomad_variable" "dev_config" {
  path = "config/dev"
  items = {
    environment = "develop"
    debug_enabled = "true"
    log_level = "INFO"
    security_hardening = "false"
    vault_address = var.vault_address
  }
}

# Outputs
output "environment" {
  value = local.environment
  description = "Current environment"
}

output "server_ip" {
  value = local.server_ip
  description = "Server IP address"
}

output "vault_kv_engines" {
  value = {
    app_secrets = vault_mount.app_secrets_dev.path
    infrastructure = vault_mount.infrastructure_dev.path
  }
  description = "Vault KV engine paths"
}

output "vault_approle" {
  value = {
    nomad_role_id = vault_approle_auth_backend_role.nomad_dev.role_id
  }
  description = "Vault AppRole information"
  sensitive = true
}

output "nomad_variables" {
  value = {
    dev_config_path = nomad_variable.dev_config.path
  }
  description = "Nomad variable paths"
}