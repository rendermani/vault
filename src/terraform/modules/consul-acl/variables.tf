# Variables for Consul ACL module

variable "acl_policies" {
  description = "Consul ACL policies configuration"
  type = map(object({
    description = string
    rules       = string
  }))
  default = {}
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