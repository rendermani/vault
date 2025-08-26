# Vault Configuration Module
# Phase 3: Terraform configuration based on proven patterns

terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.20"
    }
  }
}

# JWT Auth Backend for Nomad Workload Identity
resource "vault_auth_backend" "nomad_workload" {
  type = "jwt"
  path = "nomad-workload"
  
  description = "JWT auth backend for Nomad workload identity"
}

resource "vault_jwt_auth_backend_config" "nomad" {
  backend               = vault_auth_backend.nomad_workload.path
  jwt_validation_pubkeys = [var.nomad_jwt_public_key]
  bound_issuer          = var.nomad_issuer_url
  default_role          = "nomad-workload"
}

# Secret Engines
resource "vault_mount" "kv" {
  path        = "secret"
  type        = "kv-v2"
  description = "KV v2 secret engine for application secrets"
  
  options = {
    version = "2"
  }
}

resource "vault_mount" "nomad_secrets" {
  path        = "nomad-secrets" 
  type        = "kv-v2"
  description = "KV v2 secret engine for Nomad-specific secrets"
  
  options = {
    version = "2"
  }
}

resource "vault_mount" "traefik_secrets" {
  path        = "traefik-secrets"
  type        = "kv-v2" 
  description = "KV v2 secret engine for Traefik secrets"
  
  options = {
    version = "2"
  }
}

# PKI Engine for Internal Certificates
resource "vault_mount" "pki" {
  path                      = "pki"
  type                      = "pki"
  description               = "PKI engine for internal certificate management"
  default_lease_ttl_seconds = 86400    # 1 day
  max_lease_ttl_seconds     = 31536000 # 1 year
}

resource "vault_pki_secret_backend_root_cert" "internal_ca" {
  backend = vault_mount.pki.path
  
  type                 = "internal"
  common_name          = "${var.environment}.internal"
  ttl                  = "31536000" # 1 year
  format              = "pem"
  private_key_format  = "der"
  key_type            = "rsa"
  key_bits            = 4096
  
  exclude_cn_from_sans = true
  organization         = var.organization
  ou                  = var.organizational_unit
}

resource "vault_pki_secret_backend_config_urls" "config_urls" {
  backend                 = vault_mount.pki.path
  issuing_certificates    = ["${var.vault_address}/v1/pki/ca"]
  crl_distribution_points = ["${var.vault_address}/v1/pki/crl"]
}

# Policies
resource "vault_policy" "nomad_workload" {
  name = "nomad-workload-policy"
  
  policy = templatefile("${path.module}/policies/nomad-workload.hcl", {
    environment = var.environment
    kv_path     = vault_mount.kv.path
  })
}

resource "vault_policy" "traefik" {
  name = "traefik-policy"
  
  policy = templatefile("${path.module}/policies/traefik.hcl", {
    environment     = var.environment
    traefik_secrets = vault_mount.traefik_secrets.path
    pki_path       = vault_mount.pki.path
  })
}

resource "vault_policy" "nomad_server" {
  name = "nomad-server-policy"
  
  policy = templatefile("${path.module}/policies/nomad-server.hcl", {
    environment    = var.environment
    nomad_secrets  = vault_mount.nomad_secrets.path
    pki_path      = vault_mount.pki.path
  })
}

# JWT Auth Roles
resource "vault_jwt_auth_backend_role" "nomad_workload" {
  backend   = vault_auth_backend.nomad_workload.path
  role_name = "nomad-workload"
  
  token_policies = [vault_policy.nomad_workload.name]
  
  bound_audiences   = ["nomad.io"]
  bound_claims_type = "glob"
  bound_claims = {
    nomad_namespace = var.nomad_namespace
    nomad_job_id    = "*"
  }
  
  user_claim      = "nomad_job_id"
  role_type       = "jwt"
  token_ttl       = 3600  # 1 hour
  token_max_ttl   = 7200  # 2 hours
}

resource "vault_jwt_auth_backend_role" "traefik" {
  backend   = vault_auth_backend.nomad_workload.path
  role_name = "traefik"
  
  token_policies = [vault_policy.traefik.name]
  
  bound_audiences   = ["nomad.io"]
  bound_claims_type = "string"
  bound_claims = {
    nomad_namespace = var.nomad_namespace
    nomad_job_id    = "traefik"
  }
  
  user_claim      = "nomad_job_id"
  role_type       = "jwt"
  token_ttl       = 3600  # 1 hour
  token_max_ttl   = 14400 # 4 hours
}

# PKI Roles
resource "vault_pki_secret_backend_role" "internal_services" {
  backend = vault_mount.pki.path
  name    = "internal-services"
  
  ttl     = "86400"  # 1 day
  max_ttl = "604800" # 1 week
  
  allow_localhost    = true
  allow_bare_domains = false
  allow_subdomains   = true
  allow_glob_domains = false
  
  allowed_domains = [
    "${var.environment}.internal",
    "consul.service.consul",
    "nomad.service.consul", 
    "vault.service.consul"
  ]
  
  generate_lease = true
  key_type       = "rsa"
  key_bits       = 2048
}

# Database secrets engine (if enabled)
resource "vault_database_secrets_mount" "database" {
  count = var.enable_database_secrets ? 1 : 0
  
  path = "database"
  
  postgresql {
    name           = "postgresql-${var.environment}"
    username       = var.database_username
    password       = var.database_password
    connection_url = "postgresql://{{username}}:{{password}}@${var.database_host}:${var.database_port}/${var.database_name}?sslmode=require"
    
    verify_connection = true
    allowed_roles     = ["app-role"]
  }
}

resource "vault_database_secret_backend_role" "app_role" {
  count   = var.enable_database_secrets ? 1 : 0
  backend = vault_database_secrets_mount.database[0].path
  name    = "app-role"
  db_name = "postgresql-${var.environment}"
  
  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';",
    "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";"
  ]
  
  default_ttl = 3600  # 1 hour
  max_ttl     = 86400 # 1 day
}