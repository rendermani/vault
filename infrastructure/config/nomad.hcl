# Nomad Server/Client Configuration
datacenter = "dc1"
data_dir = "/opt/nomad/data"
log_level = "INFO"

# Server configuration
server {
  enabled = true
  bootstrap_expect = 1
  
  # Enable the scheduler to preempt jobs
  default_scheduler_config {
    preemption_config {
      batch_scheduler_enabled = true
      system_scheduler_enabled = true
      service_scheduler_enabled = true
    }
  }
}

# Client configuration
client {
  enabled = true
  
  # Host volumes for persistent storage
  host_volume "vault-develop-data" {
    path = "/opt/nomad/volumes/vault-develop-data"
    read_only = false
  }
  
  host_volume "vault-develop-config" {
    path = "/opt/nomad/volumes/vault-develop-config"
    read_only = false
  }
  
  host_volume "vault-develop-logs" {
    path = "/opt/nomad/volumes/vault-develop-logs"
    read_only = false
  }
  
  host_volume "vault-staging-data" {
    path = "/opt/nomad/volumes/vault-staging-data"
    read_only = false
  }
  
  host_volume "vault-staging-config" {
    path = "/opt/nomad/volumes/vault-staging-config"
    read_only = false
  }
  
  host_volume "vault-staging-logs" {
    path = "/opt/nomad/volumes/vault-staging-logs"
    read_only = false
  }
  
  host_volume "vault-production-data" {
    path = "/opt/nomad/volumes/vault-production-data"
    read_only = false
  }
  
  host_volume "vault-production-config" {
    path = "/opt/nomad/volumes/vault-production-config"
    read_only = false
  }
  
  host_volume "vault-production-logs" {
    path = "/opt/nomad/volumes/vault-production-logs"
    read_only = false
  }
  
  host_volume "traefik-certs" {
    path = "/opt/nomad/volumes/traefik-certs"
    read_only = false
  }
  
  host_volume "traefik-config" {
    path = "/opt/nomad/volumes/traefik-config"
    read_only = false
  }
}

# Consul integration
consul {
  address = "127.0.0.1:8500"
  server_service_name = "nomad"
  client_service_name = "nomad-client"
  auto_advertise = true
  server_auto_join = true
  client_auto_join = true
}

# Vault integration
vault {
  enabled = true
  address = "http://localhost:8200"
}

# UI
ui {
  enabled = true
}

# Telemetry
telemetry {
  collection_interval = "1s"
  disable_hostname = true
  prometheus_metrics = true
  publish_allocation_metrics = true
  publish_node_metrics = true
}