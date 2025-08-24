# Admin policy - full access to Vault
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Root protection - prevent accidental root operations
path "auth/token/root" {
  capabilities = ["deny"]
}

# Audit log access
path "sys/audit/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Policy management
path "sys/policies/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Auth method management
path "sys/auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Secrets engine management
path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

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