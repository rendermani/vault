# Traefik Pack Variables - Production Configuration
# Optimized for Phase 6 deployment with enterprise security features

# === Core Traefik Configuration ===
variable "traefik_version" {
  description = "Traefik Docker image version"
  type        = string
  default     = "v3.1"
}

variable "region" {
  description = "Nomad region"
  type        = string
  default     = "global"
}

variable "datacenter" {
  description = "Nomad datacenter"
  type        = string
  default     = "dc1"
}

variable "count" {
  description = "Number of Traefik instances for high availability"
  type        = number
  default     = 3
  
  validation {
    condition     = var.count >= 1 && var.count <= 5
    error_message = "Instance count must be between 1 and 5."
  }
}

# === Vault Integration ===
variable "vault_integration" {
  description = "Enable Vault integration for secrets management"
  type        = bool
  default     = true
}

variable "vault_agent_enabled" {
  description = "Enable Vault Agent sidecar for secret templating"
  type        = bool
  default     = true
}

variable "vault_policies" {
  description = "Vault policies for Traefik workload identity"
  type        = list(string)
  default     = ["traefik-policy", "ssl-certificates"]
}

variable "vault_role" {
  description = "Vault JWT role for workload authentication"
  type        = string
  default     = "traefik"
}

variable "vault_address" {
  description = "Vault server address"
  type        = string
  default     = "https://vault.service.consul:8200"
}

# === SSL/TLS and ACME Configuration ===
variable "acme_enabled" {
  description = "Enable Let's Encrypt ACME for automatic SSL certificates"
  type        = bool
  default     = true
}

variable "acme_email" {
  description = "Email for Let's Encrypt ACME registration"
  type        = string
  default     = "ops@cloudya.net"
}

variable "acme_ca_server" {
  description = "ACME CA server URL (use staging for testing)"
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
  # Staging: "https://acme-staging-v02.api.letsencrypt.org/directory"
}

variable "acme_dns_challenge" {
  description = "DNS challenge provider configuration"
  type = object({
    provider = string
    delay    = string
  })
  default = {
    provider = "cloudflare"
    delay    = "60"
  }
}

variable "domains" {
  description = "Domains for SSL certificates"
  type        = list(string)
  default = [
    "vault.cloudya.net",
    "consul.cloudya.net", 
    "nomad.cloudya.net",
    "traefik.cloudya.net"
  ]
}

# === Service Discovery ===
variable "consul_integration" {
  description = "Enable Consul service discovery"
  type        = bool
  default     = true
}

variable "consul_address" {
  description = "Consul server address"
  type        = string
  default     = "consul.service.consul:8500"
}

variable "nomad_provider_enabled" {
  description = "Enable Nomad provider for service discovery"
  type        = bool
  default     = true
}

variable "nomad_address" {
  description = "Nomad server address"
  type        = string
  default     = "nomad.service.consul:4646"
}

# === Network and Ports ===
variable "entrypoints" {
  description = "Traefik entrypoints configuration"
  type = object({
    web = object({
      port            = number
      redirect_to_tls = bool
    })
    websecure = object({
      port = number
    })
    traefik = object({
      port = number
    })
    metrics = object({
      port = number
    })
  })
  default = {
    web = {
      port            = 80
      redirect_to_tls = true
    }
    websecure = {
      port = 443  
    }
    traefik = {
      port = 8080
    }
    metrics = {
      port = 8082
    }
  }
}

variable "host_network" {
  description = "Use host networking mode for better performance"
  type        = bool
  default     = true
}

# === Resource Allocation ===
variable "resources" {
  description = "Resource requirements for Traefik"
  type = object({
    cpu        = number
    memory     = number
    memory_max = number
  })
  default = {
    cpu        = 1000
    memory     = 1024
    memory_max = 2048
  }
}

variable "vault_agent_resources" {
  description = "Resource requirements for Vault Agent sidecar"
  type = object({
    cpu    = number
    memory = number
  })
  default = {
    cpu    = 200
    memory = 256
  }
}

# === Placement and Constraints ===
variable "constraints" {
  description = "Nomad constraints for Traefik placement"
  type = list(object({
    attribute = string
    operator  = string
    value     = string
  }))
  default = [
    {
      attribute = "${attr.kernel.name}"
      operator  = "="
      value     = "linux"
    },
    {
      attribute = "${node.class}"
      operator  = "="
      value     = "system"
    }
  ]
}

variable "spread" {
  description = "Spread configuration for high availability"
  type = list(object({
    attribute = string
    target    = string
    percent   = number
  }))
  default = [
    {
      attribute = "${node.datacenter}"
      target    = "dc1"
      percent   = 100
    }
  ]
}

# === Security Configuration ===
variable "dashboard_enabled" {
  description = "Enable Traefik dashboard (secure access only)"
  type        = bool
  default     = true
}

variable "dashboard_auth" {
  description = "Enable dashboard authentication via Vault"
  type        = bool
  default     = true
}

variable "api_insecure" {
  description = "NEVER enable in production - dev/test only"
  type        = bool
  default     = false
}

variable "tls_options" {
  description = "TLS security configuration"
  type = object({
    min_version        = string
    cipher_suites     = list(string)
    curve_preferences = list(string)
    sni_strict        = bool
  })
  default = {
    min_version = "VersionTLS12"
    cipher_suites = [
      "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
      "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305",
      "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
      "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
      "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305",
      "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
    ]
    curve_preferences = [
      "CurveP521",
      "CurveP384",
      "CurveP256"
    ]
    sni_strict = true
  }
}

variable "middlewares" {
  description = "Default security middlewares"
  type        = list(string)
  default = [
    "secure-headers@file",
    "rate-limit@file", 
    "real-ip@file",
    "gzip@file"
  ]
}

# === Monitoring and Observability ===
variable "log_level" {
  description = "Traefik log level"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["DEBUG", "INFO", "WARN", "ERROR"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARN, ERROR"
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

variable "metrics" {
  description = "Prometheus metrics configuration"
  type = object({
    prometheus = object({
      enabled      = bool
      buckets      = list(number)
      add_entrypoints_labels = bool
      add_services_labels    = bool
      add_routers_labels     = bool
    })
  })
  default = {
    prometheus = {
      enabled                = true
      buckets               = [0.1, 0.3, 1.2, 5.0, 10.0]
      add_entrypoints_labels = true
      add_services_labels    = true
      add_routers_labels     = true
    }
  }
}

variable "tracing" {
  description = "Distributed tracing configuration"
  type = object({
    jaeger = object({
      enabled           = bool
      sampling_server   = string
      local_agent       = string
      sampling_type     = string
      sampling_param    = number
    })
  })
  default = {
    jaeger = {
      enabled         = false
      sampling_server = "http://jaeger.service.consul:5778/sampling"
      local_agent     = "jaeger.service.consul:6831"
      sampling_type   = "const"
      sampling_param  = 1.0
    }
  }
}

# === Health Checks ===
variable "health_checks" {
  description = "Health check configuration"
  type = object({
    http = object({
      enabled     = bool
      path        = string
      interval    = string
      timeout     = string
      grace_period = string
    })
    tcp = object({
      enabled     = bool
      interval    = string
      timeout     = string
    })
  })
  default = {
    http = {
      enabled      = true
      path         = "/ping"
      interval     = "10s"
      timeout      = "3s"
      grace_period = "5s"
    }
    tcp = {
      enabled  = true
      interval = "10s"
      timeout  = "3s"
    }
  }
}

# === Storage Configuration ===
variable "storage" {
  description = "Persistent storage configuration"
  type = object({
    acme_enabled = bool
    volume_name  = string
    mount_path   = string
  })
  default = {
    acme_enabled = true
    volume_name  = "traefik-acme"
    mount_path   = "/acme"
  }
}

# === Environment-specific Overrides ===
variable "environment" {
  description = "Deployment environment (development, staging, production)"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production"
  }
}

variable "debug_enabled" {
  description = "Enable debug mode (development only)"
  type        = bool
  default     = false
}

variable "pilot_enabled" {
  description = "Enable Traefik Pilot integration"
  type        = bool
  default     = false
}