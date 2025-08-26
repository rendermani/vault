# GitHub Secrets Configuration Guide

This document provides comprehensive instructions for setting up GitHub Secrets required for the automated deployment workflows.

## 🔐 Required GitHub Secrets

### Core SSH Access
```yaml
SSH_PRIVATE_KEY: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  [Your private SSH key content for root@cloudya.net access]
  -----END OPENSSH PRIVATE KEY-----
```

### Ansible Configuration
```yaml
ANSIBLE_VAULT_PASSWORD: |
  [Your Ansible Vault password for decrypting sensitive variables]
```

### HashiCorp Tool Tokens
```yaml
# Nomad bootstrap token for initial cluster setup
NOMAD_BOOTSTRAP_TOKEN: |
  [Generated Nomad bootstrap token]

# Consul bootstrap token for initial cluster setup  
CONSUL_BOOTSTRAP_TOKEN: |
  [Generated Consul bootstrap token]
```

### Cloud Provider Tokens (Optional)
```yaml
# Hetzner API token (if using Hetzner-specific resources)
HETZNER_API_TOKEN: |
  [Your Hetzner Cloud API token]

# Terraform Cloud API token (if using Terraform Cloud)
TERRAFORM_API_TOKEN: |
  [Your Terraform Cloud API token]
```

### Environment-Specific Secrets
```yaml
# Development environment secrets
VAULT_RECOVERY_KEYS_DEVELOP: |
  [Encrypted Vault recovery keys for development]

# Staging environment secrets  
VAULT_RECOVERY_KEYS_STAGING: |
  [Encrypted Vault recovery keys for staging]

# Production environment secrets
VAULT_RECOVERY_KEYS_PRODUCTION: |
  [Encrypted Vault recovery keys for production]
```

## 🛠️ Setting Up GitHub Secrets

### 1. Navigate to Repository Settings
1. Go to your repository on GitHub
2. Click on **Settings** tab
3. In the sidebar, click **Secrets and variables** → **Actions**

### 2. Add Repository Secrets
Click **New repository secret** for each required secret:

#### SSH Private Key Setup
```bash
# Generate a new SSH key pair (if needed)
ssh-keygen -t rsa -b 4096 -C "github-actions@cloudya.net" -f ~/.ssh/github_actions_key

# Copy the private key content
cat ~/.ssh/github_actions_key

# Add the public key to your server
ssh-copy-id -i ~/.ssh/github_actions_key.pub root@cloudya.net
```

#### Ansible Vault Password
```bash
# Generate a secure password
openssl rand -base64 32

# Store this password securely and add it as ANSIBLE_VAULT_PASSWORD
```

#### HashiCorp Bootstrap Tokens
```bash
# Generate Nomad bootstrap token
openssl rand -hex 32

# Generate Consul bootstrap token  
openssl rand -hex 32
```

### 3. Environment-Specific Secrets
Set up separate secrets for each environment:

#### Development Environment
- Use shorter, simpler passwords for development
- Enable debug logging and development features
- Use self-signed certificates

#### Staging Environment  
- Mirror production configuration but with staging data
- Use staging certificates and domains
- Enable comprehensive logging

#### Production Environment
- Use maximum security settings
- Implement proper certificate management
- Enable audit logging and monitoring

## 🔒 Security Best Practices

### Secret Management
1. **Principle of Least Privilege**
   - Only grant access to secrets that are absolutely necessary
   - Use environment-specific secrets where possible
   - Regularly rotate all secrets

2. **Secret Rotation Schedule**
   ```yaml
   SSH_PRIVATE_KEY: Monthly
   ANSIBLE_VAULT_PASSWORD: Quarterly  
   NOMAD_BOOTSTRAP_TOKEN: After each bootstrap
   CONSUL_BOOTSTRAP_TOKEN: After each bootstrap
   API_TOKENS: Monthly
   VAULT_RECOVERY_KEYS: Only when compromised
   ```

3. **Secret Validation**
   - Test secrets in development environment first
   - Verify secret format and structure
   - Monitor for secret usage and failures

### Environment Protection
1. **Production Environment Rules**
   - Require manual approval for production deployments
   - Limit who can approve production changes
   - Enable deployment protection rules

2. **Branch Protection**
   - Protect main branch with required reviews
   - Require status checks to pass
   - Enforce linear history

### Access Control
1. **GitHub Actions Permissions**
   ```yaml
   permissions:
     contents: read
     actions: write
     deployments: write
     id-token: write  # For OIDC authentication
   ```

2. **Server Access**
   - Use dedicated service accounts
   - Implement key-based authentication only
   - Disable password authentication
   - Use SSH key forwarding sparingly

## 🚨 Emergency Procedures

### Compromised Secrets
1. **Immediate Actions**
   ```bash
   # Rotate the compromised secret immediately
   # Update GitHub Secrets with new values
   # Deploy changes to all environments
   ```

2. **Investigation**
   - Review GitHub Actions logs for unauthorized access
   - Check server access logs
   - Audit all recent deployments

3. **Recovery**
   - Generate new secrets following security guidelines
   - Test in development environment
   - Deploy to staging for validation
   - Deploy to production with monitoring

### Secret Recovery
```bash
# If you lose Vault recovery keys, you'll need to:
# 1. Stop Vault service
# 2. Backup existing data
# 3. Reinitialize Vault cluster
# 4. Restore data from backups
# 5. Update GitHub Secrets with new recovery keys
```

## 📋 Secret Validation Checklist

### Pre-Deployment Validation
- [ ] All required secrets are present in GitHub
- [ ] SSH key has access to target servers
- [ ] Ansible vault password can decrypt variable files
- [ ] HashiCorp tokens are valid and properly formatted
- [ ] Environment-specific secrets are correctly configured

### Post-Deployment Validation  
- [ ] Secrets were used successfully during deployment
- [ ] No secrets were exposed in logs or outputs
- [ ] All services can authenticate with configured secrets
- [ ] Monitoring systems are not reporting authentication failures

## 🔧 Troubleshooting Common Issues

### SSH Connection Failures
```bash
# Test SSH connectivity manually
ssh -i /path/to/private/key root@cloudya.net

# Check SSH key format
head -1 /path/to/private/key
# Should show: -----BEGIN OPENSSH PRIVATE KEY-----

# Verify key permissions
chmod 600 /path/to/private/key
```

### Ansible Vault Issues
```bash
# Test vault password
echo "test content" | ansible-vault encrypt_string --stdin-name test_var

# Validate existing vault files
ansible-vault view path/to/encrypted/file.yml
```

### Token Authentication Failures
```bash
# Test Nomad token
export NOMAD_TOKEN="your_token_here"
nomad status

# Test Consul token  
export CONSUL_HTTP_TOKEN="your_token_here"
consul members
```

## 📚 Additional Resources

### GitHub Actions Security
- [GitHub Actions Security Hardening](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions)
- [Using Secrets in GitHub Actions](https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions)

### HashiCorp Security
- [Nomad Security](https://developer.hashicorp.com/nomad/docs/operations/security)
- [Consul Security](https://developer.hashicorp.com/consul/docs/security)
- [Vault Security](https://developer.hashicorp.com/vault/docs/internals/security)

### SSH Security
- [SSH Key Management Best Practices](https://www.ssh.com/academy/ssh-keys)
- [Hardening SSH Configuration](https://www.ssh.com/academy/ssh/sshd_config)

---

⚠️ **Important**: Never commit actual secret values to version control. This document contains examples and placeholders only.

🔐 **Security Notice**: Regularly audit and rotate all secrets according to your organization's security policies.