# Operations policy - monitoring and maintenance

# Health and status monitoring
path "sys/health" {
  capabilities = ["read"]
}

path "sys/leader" {
  capabilities = ["read"]
}

path "sys/seal-status" {
  capabilities = ["read"]
}

path "sys/host-info" {
  capabilities = ["read"]
}

# Metrics and telemetry
path "sys/metrics" {
  capabilities = ["read"]
}

path "sys/in-flight-req" {
  capabilities = ["read"]
}

# Audit log configuration - read only
path "sys/audit" {
  capabilities = ["read", "list"]
}

path "sys/audit-hash/*" {
  capabilities = ["create", "update"]
}

# Backup operations
path "sys/storage/raft/snapshot" {
  capabilities = ["read"]
}

# License and version info
path "sys/license/status" {
  capabilities = ["read"]
}

path "sys/version-history" {
  capabilities = ["read"]
}

# Mount information
path "sys/mounts" {
  capabilities = ["read", "list"]
}

path "sys/auth" {
  capabilities = ["read", "list"]
}

# Replication status (if applicable)
path "sys/replication/status" {
  capabilities = ["read"]
}

# Internal counters and activity
path "sys/internal/counters/*" {
  capabilities = ["read", "list"]
}

path "sys/activity/*" {
  capabilities = ["read", "list"]
}