# Vault Development Environment Configuration
ui = true
disable_mlock = true  # For development containers

storage "raft" {
  path = "/var/lib/vault/develop"
  node_id = "vault-develop-1"
}

# Development listener - TLS optional
listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = true  # Simplified for development
  
  # Development security headers
  x_forwarded_for_authorized_addrs = "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,127.0.0.1/32"
  x_forwarded_for_hop_skips = 0
  x_forwarded_for_reject_not_authorized = false
}

# Unix socket for local development
listener "unix" {
  address = "/tmp/vault-dev.sock"
  socket_mode = "0666"
}

api_addr = "http://localhost:8200"
cluster_addr = "http://localhost:8201"

# Development telemetry
telemetry {
  prometheus_retention_time = "10s"
  disable_hostname = false
}

# Development logging - more verbose
log_level = "debug"
log_format = "standard"  # Easier to read during development
log_file = "/var/log/vault/vault-develop.log"
log_rotate_duration = "1h"
log_rotate_max_files = 5

# Development lease settings - shorter for testing
default_lease_ttl = "1h"
max_lease_ttl = "24h"
default_max_request_duration = "30s"
cluster_name = "vault-develop"
cache_size = 32768  # Smaller cache for development

# Development settings
disable_sealwrap = true
disable_indexing = false
disable_performance_standby = true
disable_clustering = true

# Plugin directory
plugin_directory = "/etc/vault.d/plugins"

# Development audit logging
audit "file" {
  file_path = "/var/log/vault/audit-develop.log"
  format = "json"
  log_raw = false
}