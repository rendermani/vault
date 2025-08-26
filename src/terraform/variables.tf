# Variables for Vault infrastructure configuration

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "vault-infrastructure"
}

# Vault configuration
variable "vault_address" {
  description = "Vault server address"
  type        = string
  default     = "https://vault.service.consul:8200"
}

variable "vault_token" {
  description = "Vault authentication token"
  type        = string
  sensitive   = true
}

variable "vault_skip_tls_verify" {
  description = "Skip TLS verification for Vault"
  type        = bool
  default     = false
}

variable "vault_ca_cert_file" {
  description = "Path to Vault CA certificate file"
  type        = string
  default     = ""
}

# Nomad configuration
variable "nomad_address" {
  description = "Nomad server address"
  type        = string
  default     = "https://nomad.service.consul:4646"
}

variable "nomad_ca_file" {
  description = "Path to Nomad CA certificate file"
  type        = string
  default     = ""
}

variable "nomad_cert_file" {
  description = "Path to Nomad client certificate file"
  type        = string
  default     = ""
}

variable "nomad_key_file" {
  description = "Path to Nomad client key file"
  type        = string
  default     = ""
}

# Consul configuration
variable "consul_address" {
  description = "Consul server address"
  type        = string
  default     = "https://consul.service.consul:8500"
}

variable "consul_datacenter" {
  description = "Consul datacenter"
  type        = string
  default     = "dc1"
}

variable "consul_ca_file" {
  description = "Path to Consul CA certificate file"
  type        = string
  default     = ""
}

variable "consul_cert_file" {
  description = "Path to Consul client certificate file"
  type        = string
  default     = ""
}

variable "consul_key_file" {
  description = "Path to Consul client key file"
  type        = string
  default     = ""
}

# KV Engines configuration
variable "kv_engines" {
  description = "KV v2 engines configuration"
  type = map(object({
    description              = string
    default_lease_ttl_seconds = optional(number, 3600)
    max_lease_ttl_seconds    = optional(number, 86400)
    cas_required             = optional(bool, false)
    delete_version_after     = optional(string, "0s")
    max_versions            = optional(number, 10)
  }))
  default = {
    "app-secrets" = {
      description = "Application secrets storage"
      max_versions = 5
      cas_required = true
    }
    "infrastructure" = {
      description = "Infrastructure configuration secrets"
      max_versions = 10
      cas_required = true
    }
  }
}

# AppRoles configuration
variable "approles" {
  description = "AppRole authentication configuration"
  type = map(object({
    token_ttl         = optional(number, 1800)
    token_max_ttl     = optional(number, 3600)
    token_policies    = list(string)
    bind_secret_id    = optional(bool, true)
    secret_id_ttl     = optional(number, 86400)
    token_num_uses    = optional(number, 0)
    secret_id_num_uses = optional(number, 0)
  }))
  default = {}
}

# Consul ACL policies
variable "consul_acl_policies" {
  description = "Consul ACL policies configuration"
  type = map(object({
    description = string
    rules       = string
  }))
  default = {}
}

# Nomad variables
variable "nomad_variables" {
  description = "Nomad variables configuration"
  type = map(object({
    path  = string
    items = map(string)
  }))
  default = {}
}