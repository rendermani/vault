# Admin Policy - Full access for initial setup and management
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Explicit deny for dangerous operations in production
# path "sys/raw/*" {
#   capabilities = ["deny"]
# }

# path "sys/remount" {
#   capabilities = ["deny"]  
# }

# Allow admin operations
path "sys/auth" {
  capabilities = ["read", "list"]
}

path "sys/auth/*" {
  capabilities = ["create", "update", "delete", "sudo"]
}

path "sys/policies" {
  capabilities = ["read", "list"]
}

path "sys/policies/*" {
  capabilities = ["create", "update", "delete", "sudo"]
}

path "sys/mounts" {
  capabilities = ["read", "list"]
}

path "sys/mounts/*" {
  capabilities = ["create", "update", "delete", "sudo"]
}