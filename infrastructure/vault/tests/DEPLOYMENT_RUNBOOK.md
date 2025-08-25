# Vault Deployment Runbook

**Version**: 1.0  
**Date**: August 24, 2025  
**Target Environment**: Production (cloudya.net)

## Overview

This runbook provides step-by-step procedures for deploying HashiCorp Vault to production infrastructure. It covers normal deployment, emergency procedures, and rollback scenarios.

## Pre-Deployment Checklist

### Prerequisites Verification

#### Infrastructure Requirements
- [ ] Linux server (Ubuntu 20.04+ or CentOS 8+ recommended)
- [ ] Minimum 2GB RAM available
- [ ] Minimum 2 CPU cores
- [ ] 10GB+ free disk space on `/opt/vault`
- [ ] Network connectivity to HashiCorp releases
- [ ] SSH access configured for deployment user

#### GitHub Configuration
- [ ] Repository secrets configured:
  - `DEPLOY_SSH_KEY`: SSH private key for server access
- [ ] Deployment permissions verified
- [ ] Workflow permissions enabled

#### Operations Team Readiness
- [ ] Backup procedures reviewed
- [ ] Rollback procedures understood
- [ ] Unseal key distribution plan ready
- [ ] Monitoring and alerting configured
- [ ] Incident response contacts available

### System Preparation

#### Server Access
```bash
# Verify SSH access
ssh root@cloudya.net "echo 'SSH connection successful'"

# Check system resources
ssh root@cloudya.net "free -h && df -h && nproc"

# Verify internet connectivity
ssh root@cloudya.net "curl -I https://releases.hashicorp.com"
```

#### Network Configuration
```bash
# Verify firewall rules (if applicable)
ssh root@cloudya.net "iptables -L -n | grep 8200"

# Check port availability
ssh root@cloudya.net "netstat -tlnp | grep :8200 || echo 'Port 8200 available'"
```

## Deployment Procedures

### Method 1: GitHub Actions Deployment (Recommended)

#### Step 1: Initiate Deployment
1. Navigate to GitHub repository
2. Go to **Actions** tab
3. Select **"Deploy Vault to cloudya.net"** workflow
4. Click **"Run workflow"**
5. Configure parameters:
   - **Environment**: `production`
   - **Action**: `deploy`
6. Click **"Run workflow"**

#### Step 2: Monitor Deployment
```bash
# Monitor workflow progress in GitHub Actions interface
# Watch for successful completion of all steps

# Verify deployment on server
ssh root@cloudya.net "systemctl status vault"
ssh root@cloudya.net "vault status"
```

#### Step 3: Initialize Vault (First Deployment Only)
1. Return to GitHub Actions
2. Run workflow again with:
   - **Environment**: `production`
   - **Action**: `init`
3. **CRITICAL**: Immediately secure the initialization keys from `/opt/vault/init.json`

```bash
# Retrieve and secure initialization keys
ssh root@cloudya.net "cat /opt/vault/init.json"
# Copy this output to secure storage immediately
```

#### Step 4: Unseal Vault
1. Run workflow with:
   - **Environment**: `production`
   - **Action**: `unseal`
2. Verify Vault is operational:

```bash
ssh root@cloudya.net "vault status | grep Sealed"
# Should show: Sealed: false
```

### Method 2: Manual Deployment (Emergency/Backup)

#### Step 1: Deploy Using Script
```bash
# SSH to server
ssh root@cloudya.net

# Download deployment script (if not available)
curl -O https://raw.githubusercontent.com/[repo]/vault/main/scripts/deploy-vault.sh
chmod +x deploy-vault.sh

# Run deployment
./deploy-vault.sh --environment production --action install
```

#### Step 2: Manual Initialization (if needed)
```bash
# Initialize Vault
export VAULT_ADDR=http://127.0.0.1:8200
vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json > /opt/vault/init-production.json

chmod 600 /opt/vault/init-production.json

# Unseal Vault
for i in 0 1 2; do
  KEY=$(jq -r ".unseal_keys_b64[$i]" /opt/vault/init-production.json)
  vault operator unseal "$KEY"
done
```

## Post-Deployment Procedures

### Verification Steps

#### 1. Service Health Check
```bash
# Check system service
ssh root@cloudya.net "systemctl is-active vault"
ssh root@cloudya.net "systemctl is-enabled vault"

# Check Vault status
ssh root@cloudya.net "vault status"
```

#### 2. API Accessibility
```bash
# Test local API
ssh root@cloudya.net "curl -s http://127.0.0.1:8200/v1/sys/health | jq ."

# Test external API (if applicable)
curl -s http://cloudya.net:8200/v1/sys/health | jq .
```

#### 3. UI Accessibility
- Open browser to `http://cloudya.net:8200/ui`
- Verify UI loads correctly
- Test login with root token (temporarily)

### Configuration Setup

#### 1. Enable Authentication Methods
```bash
ssh root@cloudya.net << 'EOF'
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=$(jq -r '.root_token' /opt/vault/init-production.json)

# Enable userpass auth
vault auth enable userpass

# Enable AppRole auth
vault auth enable approle
EOF
```

#### 2. Configure Policies
```bash
ssh root@cloudya.net << 'EOF'
# Upload policies from repository
git clone [repository] /tmp/vault-config
cd /tmp/vault-config

# Apply policies
vault policy write admin policies/admin.hcl
vault policy write developer policies/developer.hcl
vault policy write ci-cd policies/ci-cd.hcl
vault policy write operations policies/operations.hcl
EOF
```

#### 3. Set Up Integrations
```bash
# Configure AppRoles for services
ssh root@cloudya.net "/path/to/setup-approles.sh"

# Configure Traefik integration
ssh root@cloudya.net "/path/to/setup-traefik-integration.sh"
```

### Security Hardening

#### 1. Rotate Root Token
```bash
ssh root@cloudya.net << 'EOF'
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=$(jq -r '.root_token' /opt/vault/init-production.json)

# Create new admin token
NEW_TOKEN=$(vault token create -policy=admin -display-name="admin-production" -format=json | jq -r .auth.client_token)

# Test new token
VAULT_TOKEN=$NEW_TOKEN vault token lookup-self

# Revoke root token (CAUTION: Ensure new token works first)
VAULT_TOKEN=$(jq -r '.root_token' /opt/vault/init-production.json) vault token revoke-self
EOF
```

#### 2. File Permissions Audit
```bash
ssh root@cloudya.net << 'EOF'
# Verify permissions
ls -la /opt/vault/
ls -la /opt/vault/init-production.json
ls -la /etc/systemd/system/vault.service
EOF
```

## Monitoring and Alerting

### Key Metrics to Monitor

#### System Health
- Vault service status (`systemctl status vault`)
- Vault seal status (`vault status`)
- HTTP response times
- Memory and CPU usage

#### Operational Metrics
- Authentication failures
- Policy violations
- Secret access patterns
- Backup completion status

### Alert Conditions
```bash
# Create monitoring script
cat > /usr/local/bin/vault-health-check.sh << 'EOF'
#!/bin/bash
VAULT_ADDR=http://127.0.0.1:8200

# Check if Vault is sealed
if vault status | grep -q "Sealed.*true"; then
    echo "ALERT: Vault is sealed"
    exit 1
fi

# Check if service is running
if ! systemctl is-active --quiet vault; then
    echo "ALERT: Vault service is not running"
    exit 1
fi

# Check API response
if ! curl -sf $VAULT_ADDR/v1/sys/health >/dev/null; then
    echo "ALERT: Vault API not responding"
    exit 1
fi

echo "OK: Vault is healthy"
EOF

chmod +x /usr/local/bin/vault-health-check.sh
```

## Backup Procedures

### Automated Backup Setup
```bash
# Create backup cron job
ssh root@cloudya.net "crontab -e"

# Add these lines:
# Daily backup at 2 AM
0 2 * * * /path/to/deploy-vault.sh --action backup >> /var/log/vault-backup.log 2>&1

# Weekly backup on Sunday at 3 AM
0 3 * * 0 vault operator raft snapshot save /opt/vault/backups/weekly-$(date +\%Y\%m\%d).snap >> /var/log/vault-backup.log 2>&1
```

### Manual Backup
```bash
ssh root@cloudya.net << 'EOF'
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN="<admin-token>"

# Create snapshot
vault operator raft snapshot save /opt/vault/backups/manual-$(date +%Y%m%d-%H%M%S).snap

# Verify backup
ls -la /opt/vault/backups/
EOF
```

## Rollback Procedures

### Scenario 1: Configuration Rollback
```bash
# Restore previous configuration
ssh root@cloudya.net << 'EOF'
systemctl stop vault
cp /opt/vault/backups/config/vault.hcl.backup /opt/vault/config/vault.hcl
systemctl start vault
systemctl status vault
EOF
```

### Scenario 2: Version Rollback
```bash
# Restore previous Vault binary
ssh root@cloudya.net << 'EOF'
systemctl stop vault
cp /opt/vault/backups/bin/vault.backup /opt/vault/bin/vault
chmod +x /opt/vault/bin/vault
systemctl start vault
vault version
EOF
```

### Scenario 3: Full System Restore
```bash
# Stop Vault service
ssh root@cloudya.net "systemctl stop vault"

# Restore from snapshot
ssh root@cloudya.net << 'EOF'
export VAULT_ADDR=http://127.0.0.1:8200

# Clear existing data
rm -rf /opt/vault/data/raft/*

# Start Vault
systemctl start vault

# Restore from snapshot
export VAULT_TOKEN="<admin-token>"
vault operator raft snapshot restore /opt/vault/backups/latest-backup.snap
EOF
```

## Troubleshooting Guide

### Common Issues

#### Vault Won't Start
```bash
# Check logs
ssh root@cloudya.net "journalctl -u vault -n 50"

# Check configuration syntax
ssh root@cloudya.net "vault operator diagnose"

# Check permissions
ssh root@cloudya.net "ls -la /opt/vault/"
```

#### Vault is Sealed
```bash
# Check seal status
ssh root@cloudya.net "vault status"

# Unseal manually
ssh root@cloudya.net << 'EOF'
export VAULT_ADDR=http://127.0.0.1:8200
for i in 0 1 2; do
  read -p "Enter unseal key $((i+1)): " key
  vault operator unseal "$key"
done
EOF
```

#### API Not Responding
```bash
# Check service status
ssh root@cloudya.net "systemctl status vault"

# Check port binding
ssh root@cloudya.net "netstat -tlnp | grep 8200"

# Check firewall
ssh root@cloudya.net "iptables -L -n | grep 8200"
```

### Emergency Contacts

#### Primary Contacts
- **Operations Team**: ops@cloudya.net
- **Security Team**: security@cloudya.net
- **On-call Engineer**: +1-XXX-XXX-XXXX

#### Escalation Path
1. Operations Team (0-15 minutes)
2. Security Team (15-30 minutes)
3. Architecture Team (30+ minutes)

## Maintenance Procedures

### Regular Maintenance Tasks

#### Weekly
- [ ] Review backup completion logs
- [ ] Check system resource usage
- [ ] Verify service health metrics
- [ ] Review access logs for anomalies

#### Monthly
- [ ] Test backup restore procedure
- [ ] Security audit of policies and access
- [ ] Performance analysis and optimization
- [ ] Update documentation as needed

#### Quarterly
- [ ] Full disaster recovery test
- [ ] Security penetration testing
- [ ] Capacity planning review
- [ ] Version upgrade planning

### Version Updates

#### Preparation
1. Review Vault changelog and breaking changes
2. Test upgrade in staging environment
3. Schedule maintenance window
4. Create pre-upgrade backup
5. Notify stakeholders

#### Execution
```bash
# Run upgrade using deployment script
ssh root@cloudya.net "./deploy-vault.sh --environment production --action upgrade --version <new-version>"

# Verify upgrade
ssh root@cloudya.net "vault version"
ssh root@cloudya.net "vault status"
```

---

## Appendix

### Useful Commands Reference

```bash
# Check Vault status
vault status

# List enabled auth methods
vault auth list

# List enabled secrets engines
vault secrets list

# List policies
vault policy list

# Check token info
vault token lookup-self

# Create snapshot backup
vault operator raft snapshot save backup.snap

# Restore from snapshot
vault operator raft snapshot restore backup.snap

# Check system health
curl -s http://127.0.0.1:8200/v1/sys/health | jq .
```

### File Locations Reference

```
/opt/vault/bin/vault                    # Vault binary
/opt/vault/config/vault.hcl             # Main configuration
/opt/vault/data/                        # Raft data directory
/opt/vault/logs/                        # Log files
/opt/vault/backups/                     # Backup storage
/opt/vault/init-production.json         # Initialization keys (secure!)
/etc/systemd/system/vault.service       # Systemd service file
/usr/local/bin/vault                    # Symlink to vault binary
```

---

**Document Version**: 1.0  
**Last Updated**: August 24, 2025  
**Next Review**: September 24, 2025