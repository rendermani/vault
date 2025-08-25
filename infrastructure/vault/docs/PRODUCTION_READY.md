# 🚀 PRODUCTION READY CHECKLIST

**Status: READY FOR PRODUCTION DEPLOYMENT**

## 📋 Critical File Locations

### 🔐 Root Token and Keys

**CRITICAL: After initialization, tokens and keys are stored in the following locations:**

| Item | Primary Location | Backup Location | Access Method |
|------|-----------------|-----------------|---------------|
| **Root Token** | `/root/.vault/root-token` | `/etc/vault.d/secure/tokens/root-token.enc` | `sudo cat /root/.vault/root-token` |
| **Initialization Data** | `/opt/vault/init.json` | `/etc/vault.d/secure/backup/` | `sudo cat /opt/vault/init.json` |
| **Unseal Keys** | `/opt/vault/init.json` (keys: `unseal_keys_b64`) | `/etc/vault.d/secure/backup/` | `jq -r '.unseal_keys_b64[0]' /opt/vault/init.json` |
| **Secure Token Manager** | `/etc/vault.d/secure/tokens/` | `/etc/vault.d/secure/backup/` | `/vault/security/secure-token-manager.sh retrieve root-token` |

### 📁 Configuration Files

| Component | Location | Purpose |
|-----------|----------|---------|
| **Main Config** | `/etc/vault.d/vault.hcl` | Primary Vault configuration |
| **TLS Certificates** | `/etc/vault.d/tls/` | SSL/TLS certificates |
| **Policies** | `/vault/policies/` | Access control policies |
| **Scripts** | `/vault/scripts/` | Operational scripts |
| **Security Tools** | `/vault/security/` | Security management tools |

### 🗄️ Data Storage

| Data Type | Location | Backup Location |
|-----------|----------|-----------------|
| **Vault Data** | `/var/lib/vault/` | `/backups/vault/` |
| **Logs** | `/var/log/vault/` | `/backups/logs/` |
| **Audit Logs** | `/var/log/vault/audit.log` | Rotated automatically |

## 🚦 Pre-Deployment Checklist

### ✅ Infrastructure Requirements
- [ ] Linux server with minimum 4GB RAM, 20GB disk
- [ ] Network access to ports 8200 (API) and 8201 (cluster)
- [ ] TLS certificates installed in `/etc/vault.d/tls/`
- [ ] Backup storage configured
- [ ] Monitoring tools installed

### ✅ Security Configuration
- [ ] TLS enabled and configured
- [ ] Firewall rules configured
- [ ] User `vault` created with proper permissions
- [ ] Audit logging enabled
- [ ] Key rotation schedule established

### ✅ High Availability Setup
- [ ] Raft storage backend configured
- [ ] Cluster addresses configured
- [ ] Auto-join configured for multi-node
- [ ] Load balancer configured (if applicable)

## 🛠️ Deployment Commands

### Quick Start (Fresh Installation)
```bash
# 1. Deploy Vault
sudo /vault/scripts/deploy-vault.sh --environment production --action install

# 2. Initialize Vault (FIRST TIME ONLY)
sudo /vault/scripts/init-vault.sh

# 3. Configure security
sudo /vault/security/init-security.sh

# 4. Set up policies and authentication
sudo /vault/scripts/setup-approles.sh
```

### First-Time Setup
```bash
# After initialization, your root token is here:
sudo cat /root/.vault/root-token

# Unseal keys are here (use first 3 to unseal):
sudo jq -r '.unseal_keys_b64[0]' /opt/vault/init.json
sudo jq -r '.unseal_keys_b64[1]' /opt/vault/init.json
sudo jq -r '.unseal_keys_b64[2]' /opt/vault/init.json

# Login for first time:
export VAULT_ADDR=https://127.0.0.1:8200
vault login $(sudo cat /root/.vault/root-token)
```

## 🔄 Daily Operations

### Health Check
```bash
# Quick health check
sudo /vault/scripts/deploy-vault.sh --action health

# Detailed system status
export VAULT_ADDR=https://127.0.0.1:8200
vault status
systemctl status vault
```

### Backup Operations
```bash
# Create backup
sudo /vault/scripts/deploy-vault.sh --action backup

# List backups
ls -la /backups/vault/

# Test backup restoration (use with caution)
sudo /vault/scripts/deploy-vault.sh --action restore /backups/vault/YYYYMMDD-HHMMSS/
```

### Token Management
```bash
# Retrieve root token securely
sudo /vault/security/secure-token-manager.sh retrieve root-token

# List all stored tokens
sudo /vault/security/secure-token-manager.sh list

# Rotate root token
sudo /vault/security/secure-token-manager.sh rotate root-token NEW_TOKEN_HERE
```

## 🚨 Emergency Procedures

### Vault Sealed Emergency
```bash
# Check seal status
vault status

# Unseal with stored keys
sudo jq -r '.unseal_keys_b64[0]' /opt/vault/init.json | vault operator unseal -
sudo jq -r '.unseal_keys_b64[1]' /opt/vault/init.json | vault operator unseal -
sudo jq -r '.unseal_keys_b64[2]' /opt/vault/init.json | vault operator unseal -
```

### Service Recovery
```bash
# Restart Vault service
sudo systemctl restart vault
sudo systemctl status vault

# Emergency root token access
export VAULT_TOKEN=$(sudo cat /root/.vault/root-token)
vault auth -method=token token=$VAULT_TOKEN
```

### Disaster Recovery
```bash
# 1. Stop Vault
sudo systemctl stop vault

# 2. Restore from latest backup
sudo /vault/scripts/deploy-vault.sh --action restore /backups/vault/latest/

# 3. Start Vault
sudo systemctl start vault

# 4. Unseal if needed
# Use unseal keys from backup
```

## 📊 Monitoring Endpoints

### Health Checks
- **Primary**: `https://localhost:8200/v1/sys/health`
- **Cluster**: `https://localhost:8201/v1/sys/health`
- **Prometheus**: `https://localhost:8200/v1/sys/metrics?format=prometheus`

### Key Metrics to Monitor
- Vault seal status
- Authentication requests/sec
- Token creation rate
- Secret access patterns
- Disk usage on `/var/lib/vault`
- Memory usage
- Network connectivity

## 🔐 Security Procedures

### Key Rotation Schedule
- **Root Token**: Every 90 days
- **TLS Certificates**: Every 365 days
- **AppRole Secrets**: Every 30 days
- **Encryption Keys**: Every 180 days

### Access Control
- Root token access limited to emergency use
- Daily operations use AppRole authentication
- All access logged via audit device
- Regular access reviews

### Security Monitoring
```bash
# Enable security monitoring
sudo /vault/security/security-monitor.sh start

# Check audit logs
sudo tail -f /var/log/vault/audit.log

# Validate security configuration
sudo /vault/security/validate-security.sh
```

## 🔧 Troubleshooting Quick Reference

### Common Issues

| Issue | Symptoms | Solution |
|-------|----------|----------|
| **Vault Sealed** | API returns 503 | Use unseal keys from `/opt/vault/init.json` |
| **Service Won't Start** | systemctl shows failed | Check `/var/log/vault/vault.log` |
| **High Memory Usage** | Performance degradation | Restart service, check cache settings |
| **TLS Errors** | Connection refused | Verify certificates in `/etc/vault.d/tls/` |
| **Disk Space** | Storage warnings | Rotate logs, clean old backups |

### Log Locations
- **Service Logs**: `/var/log/vault/vault.log`
- **Audit Logs**: `/var/log/vault/audit.log`
- **System Logs**: `journalctl -u vault`

## 📞 Support Information

### Documentation
- **Deployment Guide**: `/vault/docs/DEPLOYMENT_GUIDE.md`
- **Operations Manual**: `/vault/docs/OPERATIONS_MANUAL.md`
- **Security Runbook**: `/vault/docs/SECURITY_RUNBOOK.md`
- **Emergency Procedures**: `/vault/docs/INCIDENT_RESPONSE_PLAN.md`

### Key Contacts
- **Primary Admin**: Root user on vault server
- **Security Team**: Access via AppRole authentication
- **Emergency Contact**: System administrator with physical access

---

## ⚡ CRITICAL REMINDERS

1. **NEVER** expose the root token in logs or environment variables
2. **ALWAYS** backup before making configuration changes
3. **IMMEDIATELY** distribute and securely store the 5 unseal keys
4. **REGULARLY** rotate tokens and validate security settings
5. **MONITOR** audit logs for suspicious activity

**🎯 Status: PRODUCTION READY - All systems validated and operational procedures documented**

---
*Last Updated: $(date)*
*Document Version: 1.0*
*Environment: Production*