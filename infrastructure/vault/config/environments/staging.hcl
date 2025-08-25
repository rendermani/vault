# Vault Staging Environment Configuration
ui = true
disable_mlock = false

storage "raft" {
  path = "/var/lib/vault/staging"
  node_id = "vault-staging-1"
  retry_join {
    auto_join = "provider=aws region=us-west-2 tag_key=vault-env tag_value=staging"
    auto_join_scheme = "https"
  }
}

# Staging TLS Listener - Let's Encrypt staging certificates
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = false
  tls_cert_file = "/etc/vault.d/tls/staging/vault-cert.pem"
  tls_key_file  = "/etc/vault.d/tls/staging/vault-key.pem"
  tls_ca_file   = "/etc/vault.d/tls/staging/ca-cert.pem"
  tls_min_version = "tls12"
  tls_cipher_suites = "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
  
  # Staging security headers
  x_forwarded_for_authorized_addrs = "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
  x_forwarded_for_hop_skips = 0
  x_forwarded_for_reject_not_authorized = true
}

# Cluster listener for staging HA
listener "tcp" {
  address         = "0.0.0.0:8201"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = false
  tls_cert_file   = "/etc/vault.d/tls/staging/vault-cert.pem"
  tls_key_file    = "/etc/vault.d/tls/staging/vault-key.pem"
  tls_ca_file     = "/etc/vault.d/tls/staging/ca-cert.pem"
  tls_min_version = "tls12"
}

# Unix socket for staging administration
listener "unix" {
  address = "/run/vault/vault-staging.sock"
  socket_mode = "0600"
  socket_user = "vault"
  socket_group = "vault"
}

api_addr = "https://vault-staging.cloudya.net:8200"
cluster_addr = "https://vault-staging.cloudya.net:8201"

# Staging telemetry
telemetry {
  prometheus_retention_time = "60s"
  disable_hostname = false
  statsd_address = "127.0.0.1:8125"
}

# Staging logging - production-like but with more detail
log_level = "info"
log_format = "json"
log_file = "/var/log/vault/vault-staging.log"
log_rotate_duration = "12h"
log_rotate_max_files = 10

# Staging lease settings - production-like
default_lease_ttl = "24h"
max_lease_ttl = "168h"
default_max_request_duration = "60s"
cluster_name = "vault-staging"
cache_size = 65536

# Staging security settings
disable_sealwrap = false
disable_indexing = false
disable_performance_standby = false
disable_clustering = false

# Plugin directory
plugin_directory = "/etc/vault.d/plugins"

# Auto-unseal for staging (AWS KMS example)
# seal "awskms" {
#   region     = "us-west-2"
#   kms_key_id = "alias/vault-staging-unseal-key"
# }