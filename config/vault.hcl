ui = true
disable_mlock = false

storage "raft" {
  path = "/var/lib/vault"
  node_id = "vault-1"
  retry_join {
    auto_join = "provider=aws region=us-west-2 tag_key=vault tag_value=server"
    auto_join_scheme = "https"
  }
}

# Production TLS Listener
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = false
  tls_cert_file = "/etc/vault.d/tls/vault-cert.pem"
  tls_key_file  = "/etc/vault.d/tls/vault-key.pem"
  tls_ca_file   = "/etc/vault.d/tls/ca-cert.pem"
  tls_min_version = "tls12"
  tls_cipher_suites = "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305"
  tls_prefer_server_cipher_suites = true
  tls_require_and_verify_client_cert = false
  
  # Security headers
  x_forwarded_for_authorized_addrs = "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
  x_forwarded_for_hop_skips = 0
  x_forwarded_for_reject_not_authorized = true
}

# Cluster listener for HA
listener "tcp" {
  address         = "0.0.0.0:8201"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = false
  tls_cert_file   = "/etc/vault.d/tls/vault-cert.pem"
  tls_key_file    = "/etc/vault.d/tls/vault-key.pem"
  tls_ca_file     = "/etc/vault.d/tls/ca-cert.pem"
  tls_min_version = "tls12"
}

# Unix socket listener for local administration
listener "unix" {
  address = "/run/vault/vault.sock"
  socket_mode = "0600"
  socket_user = "vault"
  socket_group = "vault"
}

api_addr = "https://vault.cloudya.net:8200"
cluster_addr = "https://vault.cloudya.net:8201"

# Enhanced telemetry with security metrics
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname = false
  statsite_address = "127.0.0.1:8125"
  statsd_address = "127.0.0.1:8125"
  circonus_api_token = ""
  circonus_api_app = "vault"
  circonus_api_url = "https://api.circonus.com/v2"
  circonus_submission_interval = "10s"
  circonus_submission_url = ""
  circonus_check_id = ""
  circonus_check_force_metric_activation = "false"
  circonus_check_instance_id = ""
  circonus_check_search_tag = ""
  circonus_check_display_name = ""
  circonus_check_tags = ""
  circonus_broker_id = ""
  circonus_broker_select_tag = ""
}

# Comprehensive logging
log_level = "info"
log_format = "json"
log_file = "/var/log/vault/vault.log"
log_rotate_duration = "24h"
log_rotate_max_files = 15

# Security and performance settings
default_lease_ttl = "168h"
max_lease_ttl = "720h"
default_max_request_duration = "90s"
cluster_name = "vault-prod"
cache_size = 131072
disable_sealwrap = false
disable_indexing = false
disable_performance_standby = false
disable_clustering = false

# Plugin directory
plugin_directory = "/etc/vault.d/plugins"

# Entropy augmentation
entropy "seal" {
  mode = "augmentation"
}

# HSM/Auto-unseal configuration (commented out - configure based on your HSM)
# seal "pkcs11" {
#   lib = "/usr/lib/softhsm/libsofthsm2.so"
#   slot = "0"
#   pin = "vault-hsm-pin"
#   key_label = "vault-key"
#   hmac_key_label = "vault-hmac-key"
#   generate_key = "true"
# }

# Audit devices - will be enabled via API
# audit "file" {
#   file_path = "/var/log/vault/audit.log"
# }
# 
# audit "syslog" {
#   facility = "AUTH"
#   tag = "vault"
# }