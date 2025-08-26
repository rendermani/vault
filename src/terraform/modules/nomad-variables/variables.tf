# Variables for Nomad variables module

variable "variables" {
  description = "Nomad variables configuration"
  type = map(object({
    path      = string
    namespace = optional(string, "default")
    items     = map(string)
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