# Nomad Variables Module

terraform {
  required_providers {
    nomad = {
      source  = "hashicorp/nomad"
      version = "~> 2.0"
    }
  }
}

# Create Nomad variables
resource "nomad_variable" "variables" {
  for_each = var.variables

  path      = each.value.path
  namespace = each.value.namespace != null ? each.value.namespace : "default"
  
  items = each.value.items
}

# Create ACL policies for variable access
resource "nomad_acl_policy" "variable_read" {
  for_each = var.variables

  name        = "${replace(each.key, "/", "-")}-read"
  description = "Read access to ${each.key} variables"

  rules_hcl = <<EOT
namespace "*" {
  variables {
    path "${each.value.path}" {
      capabilities = ["read", "list"]
    }
  }
}
EOT
}

resource "nomad_acl_policy" "variable_write" {
  for_each = var.variables

  name        = "${replace(each.key, "/", "-")}-write"
  description = "Write access to ${each.key} variables"

  rules_hcl = <<EOT
namespace "*" {
  variables {
    path "${each.value.path}" {
      capabilities = ["write", "read", "list", "destroy"]
    }
  }
}
EOT
}

# Create tokens for variable access
resource "nomad_acl_token" "variable_read_tokens" {
  for_each = var.variables

  name        = "${each.key}-read-token-${var.environment}"
  type        = "client"
  policies    = [nomad_acl_policy.variable_read[each.key].name]
  global      = false
}

resource "nomad_acl_token" "variable_write_tokens" {
  for_each = var.variables

  name        = "${each.key}-write-token-${var.environment}"
  type        = "client"
  policies    = [nomad_acl_policy.variable_write[each.key].name]
  global      = false
}