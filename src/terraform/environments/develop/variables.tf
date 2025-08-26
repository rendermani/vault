# Development environment variables
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "develop"
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "vault-infrastructure"
}

# HashiCorp service addresses for development
variable "consul_address" {
  description = "Consul server address"
  type        = string
  default     = "cloudya.net:8500"
}

variable "nomad_address" {
  description = "Nomad server address"
  type        = string
  default     = "cloudya.net:4646"
}

variable "vault_address" {
  description = "Vault server address"
  type        = string
  default     = "cloudya.net:8200"
}