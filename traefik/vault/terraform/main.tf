# Terraform configuration for HashiCorp Vault
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.4"
    }
    nomad = {
      source  = "hashicorp/nomad"
      version = "~> 2.3"
    }
  }
}

# Configure Vault provider
provider "vault" {
  address = var.vault_address
  # Token will be provided via environment variable VAULT_TOKEN
}

# Configure Nomad provider
provider "nomad" {
  address = var.nomad_address
}

# Variables
variable "vault_address" {
  description = "Vault server address"
  type        = string
  default     = "https://vault.cloudya.net"
}

variable "nomad_address" {
  description = "Nomad server address"
  type        = string
  default     = "http://localhost:4646"
}

variable "organization_name" {
  description = "Organization name for certificates"
  type        = string
  default     = "Cloudya"
}

variable "domain_name" {
  description = "Domain name for certificates"
  type        = string
  default     = "cloudya.net"
}

# Local values
locals {
  policies = {
    admin-policy   = file("${path.module}/../policies/admin-policy.hcl")
    cicd-policy    = file("${path.module}/../policies/cicd-policy.hcl")
    traefik-policy = file("${path.module}/../policies/traefik-policy.hcl")
  }
}

# Enable secret engines
resource "vault_mount" "kv" {
  path        = "secret"
  type        = "kv"
  options     = { version = "2" }
  description = "KV Version 2 secret engine"
}

resource "vault_mount" "pki" {
  path                      = "pki"
  type                      = "pki"
  description               = "PKI secret engine"
  default_lease_ttl_seconds = 3600     # 1 hour
  max_lease_ttl_seconds     = 31536000  # 1 year
}

resource "vault_mount" "transit" {
  path        = "transit"
  type        = "transit"
  description = "Transit secret engine for encryption"
}

resource "vault_mount" "database" {
  path        = "database"
  type        = "database"
  description = "Database secret engine"
}

# PKI Configuration
resource "vault_pki_secret_backend_root_cert" "root" {
  depends_on = [vault_mount.pki]
  
  backend              = vault_mount.pki.path
  type                 = "internal"
  common_name          = "${var.organization_name} Root CA"
  ttl                  = "315360000"  # 10 years
  format               = "pem"
  private_key_format   = "der"
  key_type             = "rsa"
  key_bits             = 4096
  exclude_cn_from_sans = true
  organization         = var.organization_name
  ou                   = "IT Department"
  country              = "US"
}

resource "vault_pki_secret_backend_config_urls" "config_urls" {
  depends_on = [vault_mount.pki]
  
  backend                 = vault_mount.pki.path
  issuing_certificates    = ["${var.vault_address}/v1/pki/ca"]
  crl_distribution_points = ["${var.vault_address}/v1/pki/crl"]
}

resource "vault_pki_secret_backend_role" "server_cert" {
  depends_on = [vault_mount.pki]
  
  backend          = vault_mount.pki.path
  name             = "server-cert"
  ttl              = 2592000  # 30 days
  max_ttl          = 31536000 # 1 year
  allow_localhost  = true
  allow_ip_sans    = true
  allowed_domains  = [var.domain_name, "localhost"]
  allow_subdomains = true
  generate_lease   = true
}

resource "vault_pki_secret_backend_role" "traefik_cert" {
  depends_on = [vault_mount.pki]
  
  backend                    = vault_mount.pki.path
  name                       = "traefik-cert"
  ttl                        = 7776000  # 90 days
  max_ttl                    = 31536000 # 1 year
  allow_wildcard_certificates = true
  allowed_domains            = [var.domain_name]
  allow_subdomains           = true
  generate_lease             = true
}

# Transit encryption key
resource "vault_transit_secret_backend_key" "app_key" {
  depends_on = [vault_mount.transit]
  
  backend = vault_mount.transit.path
  name    = "app-key"
  type    = "aes256-gcm96"
}

# Create policies
resource "vault_policy" "policies" {
  for_each = local.policies
  
  name   = each.key
  policy = each.value
}

# Enable AppRole authentication
resource "vault_auth_backend" "approle" {
  type = "approle"
  path = "approle"
}

# CI/CD AppRole
resource "vault_approle_auth_backend_role" "cicd" {
  depends_on = [vault_auth_backend.approle]
  
  backend        = vault_auth_backend.approle.path
  role_name      = "cicd"
  token_policies = ["cicd-policy"]
  token_ttl      = 3600   # 1 hour
  token_max_ttl  = 14400  # 4 hours
  secret_id_ttl  = 600    # 10 minutes
}

# Traefik AppRole
resource "vault_approle_auth_backend_role" "traefik" {
  depends_on = [vault_auth_backend.approle]
  
  backend        = vault_auth_backend.approle.path
  role_name      = "traefik"
  token_policies = ["traefik-policy"]
  token_ttl      = 86400   # 24 hours
  token_max_ttl  = 259200  # 72 hours
  secret_id_ttl  = 0       # Never expires
}

# Store initial secrets
resource "vault_generic_secret" "traefik_dashboard" {
  depends_on = [vault_mount.kv]
  
  path = "secret/traefik/dashboard"
  
  data_json = jsonencode({
    username = "admin"
    password = "change-this-password"
  })
}

resource "vault_generic_secret" "cicd_deploy" {
  depends_on = [vault_mount.kv]
  
  path = "secret/cicd/deploy"
  
  data_json = jsonencode({
    ssh_key         = "replace-with-actual-ssh-key"
    docker_password = "replace-with-actual-docker-password"
  })
}

# Outputs
output "vault_policies" {
  description = "Created Vault policies"
  value       = keys(vault_policy.policies)
}

output "vault_mounts" {
  description = "Created secret engines"
  value = {
    kv       = vault_mount.kv.path
    pki      = vault_mount.pki.path
    transit  = vault_mount.transit.path
    database = vault_mount.database.path
  }
}

output "pki_ca_cert" {
  description = "Root CA certificate"
  value       = vault_pki_secret_backend_root_cert.root.certificate
  sensitive   = true
}

output "approle_roles" {
  description = "Created AppRole roles"
  value = {
    cicd    = vault_approle_auth_backend_role.cicd.role_name
    traefik = vault_approle_auth_backend_role.traefik.role_name
  }
}

# Generate role IDs and secret IDs for reference
data "vault_approle_auth_backend_role_id" "cicd" {
  depends_on = [vault_approle_auth_backend_role.cicd]
  
  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.cicd.role_name
}

data "vault_approle_auth_backend_role_id" "traefik" {
  depends_on = [vault_approle_auth_backend_role.traefik]
  
  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.traefik.role_name
}

output "cicd_role_id" {
  description = "CI/CD AppRole Role ID"
  value       = data.vault_approle_auth_backend_role_id.cicd.role_id
  sensitive   = true
}

output "traefik_role_id" {
  description = "Traefik AppRole Role ID"
  value       = data.vault_approle_auth_backend_role_id.traefik.role_id
  sensitive   = true
}