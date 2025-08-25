# Consul Server Configuration
datacenter = "dc1"
data_dir = "/opt/consul/data"
log_level = "INFO"
server = true
bootstrap_expect = 1

# Networking
bind_addr = "0.0.0.0"
client_addr = "0.0.0.0"

# UI
ui_config {
  enabled = true
}

# Ports
ports {
  grpc = 8502
}

# Connect
connect {
  enabled = true
}

# ACL (disabled for development, enable for production)
acl = {
  enabled = false
  default_policy = "allow"
}

# Performance
performance {
  raft_multiplier = 1
}

# Logging
log_rotate_duration = "24h"
log_rotate_max_files = 5