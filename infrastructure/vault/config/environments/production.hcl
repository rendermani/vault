# Vault Production Environment Configuration
ui = false  # Disabled for security in production
disable_mlock = false

storage "raft" {
  path = "/var/lib/vault/production"
  node_id = "vault-prod-1"
  retry_join {
    auto_join = "provider=aws region=us-west-2 tag_key=vault-env tag_value=production"
    auto_join_scheme = "https"
  }
}

# Production TLS Listener - Hardened configuration
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = false
  tls_cert_file = "/etc/vault.d/tls/production/vault-cert.pem"
  tls_key_file  = "/etc/vault.d/tls/production/vault-key.pem"
  tls_ca_file   = "/etc/vault.d/tls/production/ca-cert.pem"
  tls_min_version = "tls13"  # TLS 1.3 only for production
  tls_cipher_suites = "TLS_AES_256_GCM_SHA384,TLS_CHACHA20_POLY1305_SHA256"
  tls_prefer_server_cipher_suites = true
  tls_require_and_verify_client_cert = true  # Mutual TLS for production
  
  # Production security headers - strict
  x_forwarded_for_authorized_addrs = "10.0.0.0/8"  # Only private networks
  x_forwarded_for_hop_skips = 0
  x_forwarded_for_reject_not_authorized = true
  
  # Additional production security
  x_forwarded_for_reject_not_present = true
}

# Cluster listener for production HA
listener "tcp" {
  address         = "0.0.0.0:8201"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = false
  tls_cert_file   = "/etc/vault.d/tls/production/vault-cert.pem"
  tls_key_file    = "/etc/vault.d/tls/production/vault-key.pem"
  tls_ca_file     = "/etc/vault.d/tls/production/ca-cert.pem"
  tls_min_version = "tls13"
  tls_require_and_verify_client_cert = true
}

# Unix socket for production administration - restricted
listener "unix" {
  address = "/run/vault/vault-production.sock"
  socket_mode = "0600"
  socket_user = "vault"
  socket_group = "vault"
}

api_addr = "https://vault.cloudya.net:8200"
cluster_addr = "https://vault.cloudya.net:8201"

# Production telemetry - comprehensive monitoring
telemetry {
  prometheus_retention_time = "90s"
  disable_hostname = false
  statsd_address = "127.0.0.1:8125"
  circonus_api_token = ""
  circonus_api_app = "vault-production"
  circonus_submission_interval = "10s"
}

# Production logging - security-focused
log_level = "warn"  # Minimal logging for security
log_format = "json"
log_file = "/var/log/vault/vault-production.log"
log_rotate_duration = "24h"
log_rotate_max_files = 30

# Production lease settings - security-focused
default_lease_ttl = "168h"  # 1 week
max_lease_ttl = "720h"      # 30 days
default_max_request_duration = "90s"
cluster_name = "vault-production"
cache_size = 131072  # Large cache for performance

# Production security settings - maximum security
disable_sealwrap = false
disable_indexing = false
disable_performance_standby = false
disable_clustering = false

# Plugin directory
plugin_directory = "/etc/vault.d/plugins"

# Entropy augmentation for production
entropy "seal" {
  mode = "augmentation"
}

# Production auto-unseal - HSM or cloud KMS
seal "awskms" {
  region     = "us-west-2"
  kms_key_id = "alias/vault-production-unseal-key"
  endpoint   = "https://kms.us-west-2.amazonaws.com"
}

# Production audit devices configuration
# These would be enabled via API during deployment
# audit "file" {
#   file_path = "/var/log/vault/audit-production.log"
#   format = "json"
# }
# 
# audit "syslog" {
#   facility = "AUTH"
#   tag = "vault-production"
#   format = "json"
# }