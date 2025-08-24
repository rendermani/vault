ui = true
disable_mlock = true

storage "raft" {
  path = "/opt/vault/data"
  node_id = "vault-1"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

api_addr = "http://cloudya.net:8200"
cluster_addr = "http://cloudya.net:8201"

telemetry {
  prometheus_retention_time = "30s"
  disable_hostname = false
}

log_level = "info"