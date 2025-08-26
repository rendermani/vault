# Variables for Vault KV v2 module

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