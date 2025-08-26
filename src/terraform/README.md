# Vault Infrastructure Terraform Configuration

This Terraform configuration manages the declarative infrastructure for Vault, including secrets engines, authentication methods, and integrations with Nomad and Consul.

## Architecture

```
terraform/
├── main.tf                 # Main configuration
├── variables.tf           # Variable definitions
├── outputs.tf            # Output definitions
├── versions.tf           # Provider version constraints
├── terraform.tfvars.example # Example variables
├── modules/              # Terraform modules
│   ├── vault-kv/        # KV v2 secrets engine
│   ├── vault-approle/   # AppRole authentication
│   ├── nomad-secrets/   # Nomad secrets engine
│   ├── consul-acl/      # Consul ACL policies
│   └── nomad-variables/ # Nomad variables
└── environments/        # Environment-specific configs
    ├── dev/
    ├── staging/
    └── prod/
```

## Features

### Vault KV v2 Secrets Engine
- Configurable KV stores with versioning
- Automatic policy creation (read, write, admin)
- CAS (Compare-And-Swap) support
- TTL and retention policies

### AppRole Authentication
- Secure service authentication
- Configurable token TTLs and policies
- CIDR restrictions for security
- Automatic secret ID generation

### Nomad Secrets Engine
- Dynamic Nomad token generation
- Role-based access control
- Management, client, and server roles
- Integration with Nomad ACL system

### Consul ACL Policies
- Service-specific ACL policies
- Token management for services
- Role-based access control
- Integration with Vault and Nomad

### Nomad Variables
- Secure configuration management
- Namespace-aware variables
- ACL policies for variable access
- Environment-specific configurations

## Quick Start

1. **Copy example variables:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit configuration:**
   ```bash
   vim terraform.tfvars
   ```

3. **Initialize Terraform:**
   ```bash
   terraform init
   ```

4. **Plan deployment:**
   ```bash
   terraform plan
   ```

5. **Apply configuration:**
   ```bash
   terraform apply
   ```

## Environment Management

### Development
```bash
cd environments/dev
terraform init
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

### Production
```bash
cd environments/prod
terraform init
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

## Configuration Examples

### KV Engine Configuration
```hcl
kv_engines = {
  "app-secrets" = {
    description = "Application secrets storage"
    max_versions = 5
    cas_required = true
  }
}
```

### AppRole Configuration
```hcl
approles = {
  "nomad-cluster" = {
    token_ttl = 3600
    token_policies = ["nomad-operator"]
    bind_secret_id = true
  }
}
```

### Consul ACL Policy
```hcl
consul_acl_policies = {
  "vault-integration" = {
    description = "Vault-Consul integration"
    rules = <<EOT
service_prefix "vault" {
  policy = "write"
}
EOT
  }
}
```

## Security Considerations

1. **Vault Token Security:**
   - Use minimal required permissions
   - Rotate tokens regularly
   - Store tokens securely (not in version control)

2. **Network Security:**
   - Configure CIDR restrictions for AppRoles
   - Use TLS for all communications
   - Validate certificate chains

3. **Access Control:**
   - Follow principle of least privilege
   - Use separate tokens for different services
   - Regularly audit access patterns

## Monitoring and Maintenance

1. **Health Checks:**
   ```bash
   terraform plan -detailed-exitcode
   ```

2. **State Management:**
   ```bash
   terraform state list
   terraform state show <resource>
   ```

3. **Upgrades:**
   ```bash
   terraform plan -refresh-only
   terraform apply -refresh-only
   ```

## Troubleshooting

### Common Issues

1. **Provider Authentication:**
   - Verify Vault token has sufficient permissions
   - Check TLS configuration
   - Validate service discovery

2. **Resource Dependencies:**
   - Review module dependencies
   - Check service startup order
   - Verify network connectivity

3. **State Issues:**
   - Use `terraform refresh` to sync state
   - Import existing resources if needed
   - Backup state before major changes

### Logging
Enable detailed logging:
```bash
export TF_LOG=DEBUG
export TF_LOG_PATH=./terraform.log
```

## Integration Points

- **Ansible Bootstrap:** Builds on Phase 2 infrastructure
- **Nomad Jobs:** Uses secrets and variables from this configuration  
- **Consul Services:** Leverages ACL policies for service mesh
- **Monitoring:** Integrates with observability stack

## Support

For issues and questions:
1. Check Terraform provider documentation
2. Review module-specific README files
3. Consult HashiCorp Vault documentation
4. File issues in project repository