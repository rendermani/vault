# Variables for Vault AppRole module

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