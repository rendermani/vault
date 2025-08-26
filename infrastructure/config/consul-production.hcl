# Consul Production Configuration
# High-security configuration for production environments

datacenter = "dc1-prod"
data_dir = "/opt/consul/data"
log_level = "WARN"
server = true
bootstrap_expect = 3

# Networking - Secure binding
bind_addr = "{{ GetInterfaceIP \"eth0\" }}"
client_addr = "127.0.0.1"

# Enable UI with authentication
ui_config {
  enabled = true
}

# Ports configuration
ports {
  grpc = 8502
  grpc_tls = 8503
  https = 8501
  dns = 8600
}

# TLS Configuration
tls {
  defaults {
    verify_incoming = true
    verify_outgoing = true
    verify_server_hostname = true
  }
  internal_rpc {
    verify_server_hostname = true
  }
}

cert_file = "/opt/consul/tls/consul-cert.pem"
key_file = "/opt/consul/tls/consul-key.pem"
ca_file = "/opt/consul/tls/consul-ca.pem"

# ACL Configuration - Production Security
acl = {
  enabled = true
  default_policy = "deny"
  enable_token_persistence = true
  tokens {
    initial_management = "{{ consul acl bootstrap }}"
    agent = "{{ env \"CONSUL_AGENT_TOKEN\" }}"
    default = "{{ env \"CONSUL_DEFAULT_TOKEN\" }}"
  }
}

# Gossip Encryption
encrypt = "{{ env \"CONSUL_GOSSIP_KEY\" }}"
encrypt_verify_incoming = true
encrypt_verify_outgoing = true

# Connect/Service Mesh
connect {
  enabled = true
  ca_provider = "vault"
  ca_config {
    address = "https://vault.service.consul:8200"
    token = "{{ env \"CONSUL_VAULT_TOKEN\" }}"
    root_pki_path = "connect_root"
    intermediate_pki_path = "connect_inter"
  }
}

# DNS Configuration
dns_config {
  allow_stale = true
  max_stale = "1s"
  node_ttl = "30s"
  service_ttl = "30s"
  udp_answer_limit = 3
  recursor_timeout = "2s"
  recursors = ["1.1.1.1", "8.8.8.8"]
}

# Performance Tuning
performance {
  raft_multiplier = 1
  rpc_hold_timeout = "7s"
}

# Logging and Monitoring
log_rotate_duration = "24h"
log_rotate_max_files = 30
log_json = true

# Audit logging
audit {
  enabled = true
  sink "file" {
    type = "file"
    format = "json"
    path = "/opt/consul/audit/audit.log"
    delivery_guarantee = "best-effort"
    rotate_duration = "24h"
    rotate_max_files = 30
    rotate_bytes = 134217728
  }
}

# Telemetry
telemetry {
  prometheus_retention_time = "60s"
  disable_hostname = true
}

# Limits
limits {
  request_limits {
    mode = "permissive"
    read_rate = 100.0
    write_rate = 100.0
  }
}

# Auto-backup configuration
snapshot_agent {
  http_addr = "127.0.0.1:8500"
  token = "{{ env \"CONSUL_SNAPSHOT_TOKEN\" }}"
  log {
    level = "INFO"
    enable_syslog = false
    rotate_duration = "24h"
  }
  snapshot {
    interval = "1h"
    retain = 72
    stale = false
    service = "consul-snapshot"
    deregister_after = "72h"
    lock_key = "consul-snapshot/lock"
    max_backups = 10
  }
  local_storage {
    path = "/opt/consul/snapshots"
  }
}

# Server-specific configurations
autopilot {
  cleanup_dead_servers = true
  last_contact_threshold = "200ms"
  max_trailing_logs = 250
  server_stabilization_time = "10s"
}

# Enterprise features (if available)
# license_path = "/opt/consul/license/consul.hclic"