# 🚀 Vault Production Deployment Guide

## 📋 Pre-Deployment Requirements

### System Requirements
- **OS**: Ubuntu 20.04+ or CentOS 8+
- **CPU**: 2+ cores
- **RAM**: 4GB minimum, 8GB recommended
- **Disk**: 20GB minimum, 100GB recommended
- **Network**: Ports 8200 (API), 8201 (cluster), 22 (SSH)

### Prerequisites Checklist
- [ ] Server provisioned and accessible via SSH
- [ ] Root or sudo access available
- [ ] Domain name configured (for TLS)
- [ ] Backup storage location prepared
- [ ] Network security groups/firewall rules configured

## 🔧 Step 1: Initial Server Preparation

### Connect to Server
```bash
# SSH to your server
ssh root@your-server-ip
# OR
ssh your-user@your-server-ip
sudo su -
```

### Update System
```bash
# Update package lists and system
apt update && apt upgrade -y

# Install essential packages
apt install -y curl wget unzip jq git openssl
```

### Create Directory Structure
```bash
# Create project directory
mkdir -p /vault
cd /vault

# Download or copy the vault configuration files
# (Assume you have the repository files available)
```

## 🏗️ Step 2: Deploy Vault Infrastructure

### Run Automated Deployment
```bash
# Make deployment script executable
chmod +x /vault/scripts/deploy-vault.sh

# Deploy Vault for production
/vault/scripts/deploy-vault.sh \
  --environment production \
  --action install \
  --version 1.17.3
```

**What this script does:**
1. Downloads and installs Vault binary
2. Creates vault user and directories
3. Configures systemd service
4. Sets up initial configuration
5. Starts Vault service
6. Performs health checks

### Verify Installation
```bash
# Check Vault service status
systemctl status vault

# Check Vault version
vault version

# Check Vault status (should show "Initialized: false")
export VAULT_ADDR=http://127.0.0.1:8200
vault status
```

## 🔐 Step 3: Initialize Vault (CRITICAL STEP)

### Run Initialization Script
```bash
# Initialize Vault with secure key management
/vault/scripts/init-vault.sh
```

**CRITICAL: This step generates:**
- 5 unseal keys (need 3 to unseal)
- 1 root token (master admin access)
- Saves everything to `/opt/vault/init.json`

### Secure the Keys IMMEDIATELY
```bash
# View the initialization data
cat /opt/vault/init.json

# IMMEDIATELY copy this data to secure offline storage
# Example: Copy to external drive, password manager, etc.
```

### Test Initial Access
```bash
# Get root token
ROOT_TOKEN=$(jq -r '.root_token' /opt/vault/init.json)

# Login to Vault
export VAULT_ADDR=http://127.0.0.1:8200
vault login $ROOT_TOKEN

# Verify access
vault status
```

## 🛡️ Step 4: Configure Security

### Enable TLS (Production Required)
```bash
# Run TLS certificate manager
/vault/security/tls-cert-manager.sh setup

# This will:
# - Generate or install TLS certificates
# - Update Vault configuration for HTTPS
# - Restart Vault service
```

### Initialize Security System
```bash
# Set up comprehensive security
/vault/security/init-security.sh

# This enables:
# - Audit logging
# - Security monitoring
# - Token management system
# - Emergency access procedures
```

### Update Vault Address for TLS
```bash
# After TLS is enabled
export VAULT_ADDR=https://127.0.0.1:8200

# Login again with TLS
vault login $(cat /root/.vault/root-token)
```

## 🔑 Step 5: Configure Authentication and Policies

### Set up AppRole Authentication
```bash
# Configure AppRole for applications
/vault/scripts/setup-approles.sh

# This creates:
# - AppRole authentication method
# - Policies for different access levels
# - Initial role IDs and secret IDs
```

### Verify Policy Setup
```bash
# List enabled authentication methods
vault auth list

# List policies
vault policy list

# View a policy
vault policy read developer
```

## 📊 Step 6: Enable Monitoring and Logging

### Enable Audit Logging
```bash
# Enable file audit device
vault audit enable file file_path=/var/log/vault/audit.log

# Enable syslog audit device (optional)
vault audit enable syslog facility=AUTH tag=vault
```

### Set up Security Monitoring
```bash
# Start security monitoring
/vault/security/security-monitor.sh start

# This monitors:
# - Failed login attempts
# - Unusual access patterns
# - System health metrics
# - Audit log analysis
```

## 💾 Step 7: Configure Backup Strategy

### Set up Automated Backups
```bash
# Create backup directory
mkdir -p /backups/vault

# Test backup creation
/vault/scripts/deploy-vault.sh --action backup

# Set up cron job for daily backups
echo "0 2 * * * root /vault/scripts/deploy-vault.sh --action backup" >> /etc/crontab
```

### Test Backup/Restore Process
```bash
# List backups
ls -la /backups/vault/

# Test restore (use with caution)
# /vault/scripts/deploy-vault.sh --action restore /backups/vault/BACKUP_DIR
```

## 🔄 Step 8: Configure High Availability (Optional)

### For Multi-Node Setup
```bash
# On additional nodes, modify the configuration
# Update /etc/vault.d/vault.hcl with cluster settings

# Example for node 2:
# node_id = "vault-2"
# retry_join {
#   leader_api_addr = "https://vault-1:8200"
# }
```

### Verify Cluster Status
```bash
# Check cluster members
vault operator raft list-peers

# Check cluster health
vault status
```

## ✅ Step 9: Final Validation

### Run Comprehensive Health Check
```bash
# Full system health check
/vault/scripts/deploy-vault.sh --action health

# Security validation
/vault/security/validate-security.sh

# Check all services
systemctl status vault
systemctl status vault-monitor
```

### Test All Authentication Methods
```bash
# Test root token access
vault login $(cat /root/.vault/root-token)

# Test AppRole authentication
vault write auth/approle/login role_id=YOUR_ROLE_ID secret_id=YOUR_SECRET_ID

# Test policy enforcement
vault kv put secret/test value=test-data
```

## 📋 Step 10: Production Hardening

### Security Hardening Checklist
- [ ] Root token secured and backed up offline
- [ ] Unseal keys distributed to different people
- [ ] TLS certificates installed and configured
- [ ] Firewall rules restricting access
- [ ] Audit logging enabled and monitored
- [ ] Regular backup schedule configured
- [ ] Monitoring and alerting set up
- [ ] Emergency procedures documented

### Final Configuration Review
```bash
# Review configuration
cat /etc/vault.d/vault.hcl

# Check file permissions
ls -la /etc/vault.d/
ls -la /var/lib/vault/
ls -la /root/.vault/

# Verify TLS configuration
openssl s_client -connect localhost:8200
```

## 🚀 Step 11: Go Live!

### Update DNS and Load Balancer
```bash
# Update your DNS records to point to the Vault server
# Configure load balancer if using multiple nodes
# Update application configurations to use new Vault address
```

### Final Verification
```bash
# Test from external client
export VAULT_ADDR=https://your-domain.com:8200
vault status

# Test application authentication
vault write auth/approle/login role_id=YOUR_APP_ROLE_ID secret_id=YOUR_SECRET_ID
```

## 🔧 Post-Deployment Tasks

### Documentation
1. Update `/vault/docs/PRODUCTION_READY.md` with server-specific details
2. Record all role IDs, secret IDs, and access procedures
3. Create runbooks for operational procedures
4. Document disaster recovery procedures

### Team Training
1. Train operations team on Vault management
2. Establish emergency contact procedures
3. Practice disaster recovery scenarios
4. Set up regular security reviews

## 🚨 Emergency Rollback Plan

If issues arise during deployment:

```bash
# 1. Stop Vault service
systemctl stop vault

# 2. Restore from backup if needed
/vault/scripts/deploy-vault.sh --action restore /backups/vault/LAST_GOOD_BACKUP/

# 3. Revert DNS/load balancer changes
# 4. Investigate issues in logs:
tail -f /var/log/vault/vault.log
journalctl -u vault -f
```

## 📞 Support and Troubleshooting

### Log Locations
- **Vault Service**: `/var/log/vault/vault.log`
- **Audit Logs**: `/var/log/vault/audit.log`
- **System Logs**: `journalctl -u vault`
- **Security Monitoring**: `/var/log/vault-security.log`

### Common Issues and Solutions

| Issue | Symptoms | Solution |
|-------|----------|----------|
| Vault won't start | Service failed | Check config: `/etc/vault.d/vault.hcl` |
| Cannot connect | Connection refused | Check firewall and TLS config |
| Sealed on restart | Status shows sealed | Use unseal keys from init.json |
| High memory usage | Performance issues | Check cache settings, restart service |

### Emergency Contacts
- **Primary Admin**: Person with root token access
- **Security Team**: Team with unseal keys
- **Infrastructure Team**: Server access and monitoring

---

## 🎯 Deployment Success Criteria

✅ **Deployment is successful when:**
- [ ] Vault service is running and stable
- [ ] TLS is configured and working
- [ ] Authentication methods are configured
- [ ] Policies are applied and tested
- [ ] Backups are working
- [ ] Monitoring is active
- [ ] Security validation passes
- [ ] Applications can authenticate successfully
- [ ] Emergency procedures are documented
- [ ] Team is trained and ready

---

## 📚 Next Steps

After successful deployment:
1. **Configure Applications**: Update apps to use Vault for secrets
2. **Set up Monitoring**: Configure alerting and dashboards
3. **Plan Maintenance**: Schedule regular updates and key rotations
4. **Security Reviews**: Regular security audits and penetration testing
5. **Capacity Planning**: Monitor usage and plan for scaling

---

**🚀 You now have a production-ready Vault deployment!**

*For ongoing operations, refer to:*
- **Daily Operations**: `/vault/docs/OPERATIONS_MANUAL.md`
- **Security Procedures**: `/vault/docs/SECURITY_RUNBOOK.md`
- **Emergency Response**: `/vault/docs/INCIDENT_RESPONSE_PLAN.md`
- **Token Management**: `/vault/docs/TOKEN_AND_KEY_MANAGEMENT.md`

---
*Last Updated: $(date)*
*Deployment Guide Version: 1.0*