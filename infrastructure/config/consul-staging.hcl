# Consul Staging Configuration
# Security-enabled configuration for staging/testing environments

datacenter = "dc1-staging"
data_dir = "/opt/consul/data"
log_level = "INFO"
server = true
bootstrap_expect = 3

# Networking - Moderately secure
bind_addr = "{{ GetInterfaceIP \"eth0\" }}"
client_addr = "127.0.0.1"

# Enable UI 
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

# TLS Configuration - Staging level
tls {
  defaults {
    verify_incoming = false
    verify_outgoing = true
    verify_server_hostname = false
  }
}

cert_file = "/opt/consul/tls/consul-cert.pem"
key_file = "/opt/consul/tls/consul-key.pem"
ca_file = "/opt/consul/tls/consul-ca.pem"

# ACL Configuration - Staging Security
acl = {
  enabled = true
  default_policy = "allow"
  enable_token_persistence = true
  tokens {
    initial_management = "{{ env \"CONSUL_BOOTSTRAP_TOKEN\" }}"
    agent = "{{ env \"CONSUL_AGENT_TOKEN\" }}"
    default = "{{ env \"CONSUL_DEFAULT_TOKEN\" }}"
  }
}

# Gossip Encryption
encrypt = "{{ env \"CONSUL_GOSSIP_KEY\" }}"
encrypt_verify_incoming = false
encrypt_verify_outgoing = true

# Connect/Service Mesh
connect {
  enabled = true
  ca_provider = "consul"
}

# DNS Configuration
dns_config {
  allow_stale = true
  max_stale = "5s"
  node_ttl = "60s"
  service_ttl = "60s"
  udp_answer_limit = 5
  recursor_timeout = "5s"
  recursors = ["8.8.8.8", "1.1.1.1"]
}

# Performance
performance {
  raft_multiplier = 1
}

# Logging
log_rotate_duration = "24h"
log_rotate_max_files = 7
log_json = true

# Basic telemetry
telemetry {
  prometheus_retention_time = "30s"
}

# Auto-cleanup for staging
autopilot {
  cleanup_dead_servers = true
  last_contact_threshold = "500ms"
  max_trailing_logs = 500
  server_stabilization_time = "30s"
}