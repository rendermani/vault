# Terraform configuration for Vault infrastructure
# Phase 3: Declarative Infrastructure Management

terraform {
  required_version = ">= 1.0"
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
  }

  backend "consul" {
    address = var.consul_address
    scheme  = "https"
    path    = "terraform/vault-infrastructure"
  }
}

# Provider configurations
provider "vault" {
  address          = var.vault_address
  token            = var.vault_token
  skip_tls_verify  = var.vault_skip_tls_verify
  ca_cert_file     = var.vault_ca_cert_file
}

provider "nomad" {
  address   = var.nomad_address
  ca_file   = var.nomad_ca_file
  cert_file = var.nomad_cert_file
  key_file  = var.nomad_key_file
}

provider "consul" {
  address    = var.consul_address
  datacenter = var.consul_datacenter
  ca_file    = var.consul_ca_file
  cert_file  = var.consul_cert_file
  key_file   = var.consul_key_file
}

# Local values
locals {
  environment = var.environment
  project     = var.project_name
  
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
    Component   = "vault-infrastructure"
  }
}

# Vault KV v2 Secrets Engine
module "vault_kv" {
  source = "./modules/vault-kv"
  
  kv_engines = var.kv_engines
  environment = local.environment
  tags = local.common_tags
}

# AppRole Authentication
module "vault_approle" {
  source = "./modules/vault-approle"
  
  approles = var.approles
  environment = local.environment
  tags = local.common_tags
}

# Nomad Secrets Engine
module "nomad_secrets" {
  source = "./modules/nomad-secrets"
  
  nomad_address = var.nomad_address
  nomad_ca_file = var.nomad_ca_file
  environment = local.environment
  tags = local.common_tags
}

# Consul ACL Policies
module "consul_acl" {
  source = "./modules/consul-acl"
  
  acl_policies = var.consul_acl_policies
  environment = local.environment
  tags = local.common_tags
}

# Nomad Variables
module "nomad_variables" {
  source = "./modules/nomad-variables"
  
  variables = var.nomad_variables
  environment = local.environment
  tags = local.common_tags
}