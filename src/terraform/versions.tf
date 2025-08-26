# Terraform version constraints

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
}