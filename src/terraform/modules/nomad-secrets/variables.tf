# Variables for Nomad secrets engine module

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

variable "nomad_token" {
  description = "Nomad token for Vault to use"
  type        = string
  sensitive   = true
  default     = ""
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}