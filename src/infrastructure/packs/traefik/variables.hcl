# Traefik Pack Variables
# Based on proven patterns from existing traefik configuration

variable "traefik_version" {
  description = "Traefik Docker image version"
  type        = string
  default     = "v3.0"
}

variable "vault_integration" {
  description = "Enable Vault integration for secrets management"
  type        = bool
  default     = true
}

variable "consul_integration" {
  description = "Enable Consul service discovery"
  type        = bool
  default     = true
}

variable "dashboard_enabled" {
  description = "Enable Traefik dashboard"
  type        = bool
  default     = true
}

variable "api_insecure" {
  description = "Enable insecure API access (development only)"
  type        = bool
  default     = false
}

variable "log_level" {
  description = "Log level (DEBUG, INFO, WARN, ERROR)"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["DEBUG", "INFO", "WARN", "ERROR"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARN, ERROR"
  }
}

variable "count" {
  description = "Number of Traefik instances"
  type        = number
  default     = 3
}

variable "resources" {
  description = "Resource requirements for Traefik"
  type = object({
    cpu    = number
    memory = number
  })
  default = {
    cpu    = 500
    memory = 512
  }
}

variable "constraints" {
  description = "Nomad constraints for Traefik placement"
  type = list(object({
    attribute = string
    operator  = string
    value     = string
  }))
  default = []
}

variable "vault_policies" {
  description = "Vault policies for Traefik workload"
  type        = list(string)
  default     = ["traefik-policy"]
}

variable "vault_role" {
  description = "Vault role for JWT authentication"
  type        = string
  default     = "traefik"
}

variable "acme_email" {
  description = "Email for Let's Encrypt ACME registration"
  type        = string
  default     = ""
}

variable "acme_ca_server" {
  description = "ACME CA server URL"
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "entrypoints" {
  description = "Traefik entrypoints configuration"
  type = object({
    web = object({
      port = number
    })
    websecure = object({
      port = number
    })
    traefik = object({
      port = number
    })
  })
  default = {
    web = {
      port = 80
    }
    websecure = {
      port = 443  
    }
    traefik = {
      port = 8080
    }
  }
}

variable "providers" {
  description = "Traefik providers configuration"
  type = object({
    consul_catalog = object({
      enabled   = bool
      endpoints = list(string)
    })
    nomad = object({
      enabled   = bool
      endpoints = list(string)
    })
  })
  default = {
    consul_catalog = {
      enabled   = true
      endpoints = ["consul.service.consul:8500"]
    }
    nomad = {
      enabled   = true
      endpoints = ["nomad.service.consul:4646"]
    }
  }
}

variable "middlewares" {
  description = "Default middlewares to apply"
  type        = list(string)
  default     = ["secure-headers", "rate-limit"]
}

variable "tls_options" {
  description = "TLS configuration options"
  type = object({
    min_version = string
    ciphers     = list(string)
  })
  default = {
    min_version = "VersionTLS12"
    ciphers = [
      "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
      "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305",
      "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
    ]
  }
}

variable "metrics" {
  description = "Metrics configuration"
  type = object({
    prometheus = object({
      enabled = bool
      buckets = list(number)
    })
  })
  default = {
    prometheus = {
      enabled = true
      buckets = [0.1, 0.3, 1.2, 5.0]
    }
  }
}

variable "tracing" {
  description = "Distributed tracing configuration"
  type = object({
    jaeger = object({
      enabled         = bool
      sampling_server = string
      local_agent     = string
    })
  })
  default = {
    jaeger = {
      enabled         = false
      sampling_server = "http://jaeger.service.consul:5778/sampling"
      local_agent     = "jaeger.service.consul:6831"
    }
  }
}

variable "access_log" {
  description = "Access log configuration"
  type = object({
    enabled = bool
    format  = string
    filters = object({
      status_codes   = list(string)
      retry_attempts = bool
      min_duration   = string
    })
  })
  default = {
    enabled = true
    format  = "json"
    filters = {
      status_codes   = ["400-599"]
      retry_attempts = true
      min_duration   = "10ms"
    }
  }
}