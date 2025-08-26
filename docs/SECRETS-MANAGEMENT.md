# Secrets Management and Configuration Guide

## Overview
This document outlines the proper secrets management and configuration setup for the fixed Vault infrastructure deployment system.

## Required GitHub Secrets

### Core Secrets (All Environments)
```bash
# SSH Access
SSH_PRIVATE_KEY=<your-private-ssh-key>

# Ansible Configuration  
ANSIBLE_VAULT_PASSWORD=<your-ansible-vault-password>
```

### Server Configuration
```bash
# Override default server settings
REMOTE_SERVER=<your-server-address>     # Default: cloudya.net
REMOTE_USER=<ssh-username>              # Default: root
REMOTE_PORT=<ssh-port>                  # Default: 22
```

### HashiCorp Service Addresses
```bash
# Service endpoints (auto-discovered if not set)
CONSUL_ADDRESS=<consul-host:port>       # Default: cloudya.net:8500
NOMAD_ADDRESS=<nomad-host:port>         # Default: cloudya.net:4646  
VAULT_ADDRESS=<vault-host:port>         # Default: cloudya.net:8200
```

### Authentication Tokens
```bash
# For Terraform operations
CONSUL_HTTP_TOKEN=<consul-acl-token>    # Required for staging/production
VAULT_TOKEN=<vault-root-or-admin-token> # Required for Terraform operations
```

### Optional Webhooks
```bash
# For deployment notifications
WEBHOOK_URL=<slack-or-teams-webhook-url>
```

## GitHub Variables

### HashiCorp Versions
```bash
# Override default versions
CONSUL_VERSION=1.17.0
NOMAD_VERSION=1.7.2
VAULT_VERSION=1.15.4
```

## Environment-Specific Security Levels

### Development Environment
- **Security Level**: Relaxed
- **Required Secrets**: SSH_PRIVATE_KEY, ANSIBLE_VAULT_PASSWORD
- **Features**: 
  - Debug logging enabled
  - Security hardening optional
  - ACLs disabled by default
  - Raw exec plugin enabled

### Staging Environment  
- **Security Level**: High
- **Required Secrets**: All core secrets + CONSUL_HTTP_TOKEN
- **Features**:
  - Security hardening enforced
  - ACLs enabled
  - Production-like security
  - Limited debug logging

### Production Environment
- **Security Level**: Maximum
- **Required Secrets**: All secrets required
- **Features**:
  - Maximum security hardening
  - ACLs with deny-by-default
  - TLS encryption enforced
  - No debug logging
  - Maintenance window checks
  - Security compliance validation

## Setting Up Secrets

### 1. Generate SSH Key Pair
```bash
# Generate a new SSH key for deployment
ssh-keygen -t rsa -b 4096 -C "github-actions@yourorg.com" -f deployment_key

# Add public key to server authorized_keys
ssh-copy-id -i deployment_key.pub user@your-server

# Add private key to GitHub secrets
cat deployment_key | gh secret set SSH_PRIVATE_KEY
```

### 2. Configure Ansible Vault
```bash
# Create a strong password for Ansible vault
openssl rand -base64 32 > .vault_pass

# Add to GitHub secrets
gh secret set ANSIBLE_VAULT_PASSWORD --body-file .vault_pass

# Encrypt sensitive variables
ansible-vault encrypt_string 'sensitive_value' --name 'variable_name'
```

### 3. Set Up HashiCorp Authentication
```bash
# For Consul ACL token (staging/production)
consul acl token create -description "GitHub Actions" -policy-name "terraform-policy"
gh secret set CONSUL_HTTP_TOKEN --body "your-consul-token"

# For Vault token (Terraform operations)
vault auth -method=userpass username=terraform
gh secret set VAULT_TOKEN --body "your-vault-token"
```

## One-Button Deployment Setup

### Quick Setup Script
```bash
#!/bin/bash
# setup-secrets.sh - Quick secrets configuration

echo "Setting up GitHub secrets for one-button deployment..."

# Core secrets
gh secret set SSH_PRIVATE_KEY --body-file ~/.ssh/deployment_key
gh secret set ANSIBLE_VAULT_PASSWORD --body "$(openssl rand -base64 32)"

# Server configuration (update as needed)
gh secret set REMOTE_SERVER --body "your-server.example.com"
gh secret set REMOTE_USER --body "deploy"

# HashiCorp versions
gh variable set CONSUL_VERSION --body "1.17.0"
gh variable set NOMAD_VERSION --body "1.7.2" 
gh variable set VAULT_VERSION --body "1.15.4"

echo "Basic secrets configured! Additional secrets may be needed for staging/production."
```

## Security Best Practices

### 1. Secret Rotation
- Rotate SSH keys every 90 days
- Rotate HashiCorp tokens every 30 days
- Update Ansible vault password quarterly

### 2. Access Control
- Use GitHub environment protection rules
- Require reviews for production deployments
- Implement branch protection on main/production branches

### 3. Monitoring
- Enable GitHub Actions audit logs
- Monitor secret usage and access patterns
- Set up alerts for failed authentications

## Troubleshooting Common Issues

### SSH Connection Failures
```bash
# Debug SSH connectivity
ssh -vvv user@server

# Check key permissions
chmod 600 ~/.ssh/deployment_key
```

### Ansible Vault Issues
```bash
# Test vault password
echo "test" | ansible-vault encrypt_string --stdin-name "test"

# Verify vault file decryption
ansible-vault view encrypted_file.yml
```

### HashiCorp Service Connectivity
```bash
# Test Consul connectivity
curl -s http://server:8500/v1/status/leader

# Test Nomad connectivity  
curl -s http://server:4646/v1/status/leader

# Test Vault connectivity
curl -s http://server:8200/v1/sys/health
```

## Deployment Validation

### Pre-Deployment Checklist
- [ ] All required secrets are configured
- [ ] SSH key is properly formatted and accessible
- [ ] Server is accessible via SSH
- [ ] HashiCorp services are running (if updating existing)
- [ ] Consul backend is accessible for Terraform state
- [ ] Environment-specific variables are set

### Post-Deployment Validation
- [ ] All services are running and healthy
- [ ] Security compliance checks pass (production)
- [ ] State files are properly stored in Consul
- [ ] Deployment state markers are created
- [ ] Monitoring and alerting are functional (production)

## Support and Maintenance

### Regular Maintenance Tasks
1. **Weekly**: Review deployment logs and security events
2. **Monthly**: Rotate authentication tokens
3. **Quarterly**: Update HashiCorp versions and security patches
4. **Annually**: Full security audit and penetration testing

### Emergency Procedures
1. **Service Outage**: Use rollback workflow with previous state
2. **Security Breach**: Immediately rotate all secrets and tokens
3. **Data Loss**: Restore from Consul state backup
4. **Access Loss**: Use emergency SSH key or console access

For additional support, refer to the main README.md or contact the platform engineering team.