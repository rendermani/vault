# 🚨 Vault Disaster Recovery Plan

## 🎯 Recovery Objectives

### Recovery Time Objective (RTO)
- **Critical Systems**: < 15 minutes
- **Full Service Restoration**: < 2 hours
- **Complete Data Recovery**: < 4 hours

### Recovery Point Objective (RPO)
- **Maximum Data Loss**: < 15 minutes (automated backups every 15 minutes)
- **Configuration Loss**: 0 (version controlled)

## 🚨 Emergency Response Team

### Primary Contacts
| Role | Name | Phone | Email | Backup |
|------|------|--------|-------|--------|
| **Incident Commander** | [Primary Admin] | [Phone] | [Email] | [Backup Person] |
| **Vault Administrator** | [Vault Admin] | [Phone] | [Email] | [Backup Admin] |
| **Security Officer** | [Security Lead] | [Phone] | [Email] | [Backup Security] |
| **Infrastructure Team** | [Infra Lead] | [Phone] | [Email] | [Backup Infra] |

### Escalation Matrix
1. **Level 1**: Vault Administrator (0-15 minutes)
2. **Level 2**: Incident Commander (15-30 minutes)
3. **Level 3**: Security Officer + Management (30+ minutes)

## 🔥 Emergency Scenarios

### Scenario 1: Vault Service Failure

#### Symptoms
- Vault service not responding
- Health check endpoints failing
- Applications unable to authenticate

#### Immediate Response (0-5 minutes)
```bash
# 1. Check service status
systemctl status vault

# 2. Check system resources
df -h
free -h
top -b -n1 | head -20

# 3. Check Vault logs
tail -50 /var/log/vault/vault.log
journalctl -u vault -n 50

# 4. Attempt service restart
systemctl restart vault
sleep 10
vault status
```

#### Recovery Actions (5-15 minutes)
```bash
# If restart fails, check configuration
vault server -config=/etc/vault.d/vault.hcl -test

# If configuration is invalid, restore from backup
cp /backups/vault/latest/vault-config.tar.gz /tmp/
tar -xzf /tmp/vault-config.tar.gz -C /

# Restart with restored config
systemctl restart vault
```

### Scenario 2: Vault Sealed Emergency

#### Symptoms
- Vault status shows "Sealed: true"
- API returns 503 Service Unavailable
- Applications cannot access secrets

#### Immediate Response (0-2 minutes)
```bash
# 1. Confirm seal status
export VAULT_ADDR=https://127.0.0.1:8200
vault status

# 2. Locate unseal keys
sudo cat /opt/vault/init.json | jq -r '.unseal_keys_b64[]'
```

#### Recovery Actions (2-5 minutes)
```bash
# 3. Unseal with first 3 keys
KEY1=$(sudo jq -r '.unseal_keys_b64[0]' /opt/vault/init.json)
KEY2=$(sudo jq -r '.unseal_keys_b64[1]' /opt/vault/init.json)
KEY3=$(sudo jq -r '.unseal_keys_b64[2]' /opt/vault/init.json)

vault operator unseal "$KEY1"
vault operator unseal "$KEY2"
vault operator unseal "$KEY3"

# 4. Verify unsealed
vault status
```

### Scenario 3: Complete Server Loss

#### Symptoms
- Server unreachable
- Hardware failure
- Data center outage

#### Recovery Actions (0-30 minutes)

**Step 1: Provision New Server**
```bash
# Deploy to new server
# Copy repository to new server
scp -r /vault/ root@new-server:/vault/

# SSH to new server
ssh root@new-server
```

**Step 2: Restore from Backup**
```bash
# Install Vault
/vault/scripts/deploy-vault.sh --environment production --action install

# Stop Vault service
systemctl stop vault

# Find latest backup
LATEST_BACKUP=$(ls -t /backups/vault/ | head -1)
echo "Restoring from: $LATEST_BACKUP"

# Restore data
tar -xzf "/backups/vault/$LATEST_BACKUP/vault-data.tar.gz" -C /var/lib/
tar -xzf "/backups/vault/$LATEST_BACKUP/vault-config.tar.gz" -C /
tar -xzf "/backups/vault/$LATEST_BACKUP/vault-credentials.tar.gz" -C /root/

# Set permissions
chown -R vault:vault /var/lib/vault
chmod 600 /root/.vault/*

# Start Vault
systemctl start vault
sleep 10

# Unseal Vault
vault operator unseal $(sudo jq -r '.unseal_keys_b64[0]' /opt/vault/init.json)
vault operator unseal $(sudo jq -r '.unseal_keys_b64[1]' /opt/vault/init.json)
vault operator unseal $(sudo jq -r '.unseal_keys_b64[2]' /opt/vault/init.json)
```

**Step 3: Update DNS and Load Balancer**
```bash
# Update DNS records to point to new server
# Update load balancer configuration
# Notify applications of new endpoint
```

### Scenario 4: Data Corruption

#### Symptoms
- Raft storage errors
- Vault cannot start
- Data consistency issues

#### Recovery Actions (0-60 minutes)
```bash
# 1. Stop Vault
systemctl stop vault

# 2. Backup current state
cp -r /var/lib/vault /var/lib/vault.corrupted

# 3. Restore from Raft snapshot
LATEST_BACKUP=$(ls -t /backups/vault/ | head -1)
if [ -f "/backups/vault/$LATEST_BACKUP/vault.snap" ]; then
    # Remove corrupted data
    rm -rf /var/lib/vault/*
    
    # Start Vault to initialize
    systemctl start vault
    sleep 10
    
    # Initialize if needed
    if vault status 2>&1 | grep -q "Initialized.*false"; then
        vault operator init -recovery-shares=1 -recovery-threshold=1 -format=json > /root/.vault/recovery-init.json
    fi
    
    # Restore from snapshot
    vault operator raft snapshot restore "/backups/vault/$LATEST_BACKUP/vault.snap"
    
    # Restart and unseal
    systemctl restart vault
    sleep 10
    vault operator unseal $(sudo jq -r '.unseal_keys_b64[0]' /opt/vault/init.json)
    vault operator unseal $(sudo jq -r '.unseal_keys_b64[1]' /opt/vault/init.json)
    vault operator unseal $(sudo jq -r '.unseal_keys_b64[2]' /opt/vault/init.json)
fi
```

### Scenario 5: Lost Root Token and Unseal Keys

#### Symptoms
- Cannot access Vault with root token
- No unseal keys available
- Complete administrative lockout

#### Recovery Actions (EXTREME SCENARIO)
```bash
# This scenario requires complete reinitialization
# ALL DATA WILL BE LOST

# 1. Stop Vault
systemctl stop vault

# 2. Remove all data
rm -rf /var/lib/vault/*
rm -f /root/.vault/*

# 3. Start fresh
systemctl start vault

# 4. Initialize new Vault
vault operator init -key-shares=5 -key-threshold=3 -format=json > /opt/vault/new-init.json

# 5. Extract new keys
UNSEAL_KEYS=$(jq -r '.unseal_keys_b64[]' /opt/vault/new-init.json)
ROOT_TOKEN=$(jq -r '.root_token' /opt/vault/new-init.json)

# 6. Save new credentials
echo "$ROOT_TOKEN" > /root/.vault/root-token
chmod 600 /root/.vault/root-token

# 7. Unseal with new keys
echo "$UNSEAL_KEYS" | head -3 | while read key; do
    vault operator unseal "$key"
done

# 8. Restore data from backups if available
# NOTE: This will require manual restoration of all secrets
```

## 💾 Backup and Recovery Procedures

### Automated Backup System

#### Continuous Backup Script
```bash
# Create automated backup system
cat > /vault/scripts/continuous-backup.sh << 'EOF'
#!/bin/bash

BACKUP_DIR="/backups/vault"
RETENTION_DAYS=30
export VAULT_ADDR=https://127.0.0.1:8200

# Create timestamped backup directory
BACKUP_NAME="$(date +%Y%m%d-%H%M%S)"
CURRENT_BACKUP="$BACKUP_DIR/$BACKUP_NAME"
mkdir -p "$CURRENT_BACKUP"

# Backup Raft snapshot
if [[ -f /root/.vault/root-token ]]; then
    export VAULT_TOKEN=$(cat /root/.vault/root-token)
    vault operator raft snapshot save "$CURRENT_BACKUP/vault.snap" 2>/dev/null || {
        echo "Warning: Could not create Raft snapshot"
    }
fi

# Backup configuration files
tar -czf "$CURRENT_BACKUP/vault-config.tar.gz" /etc/vault.d/ 2>/dev/null

# Backup data directory
tar -czf "$CURRENT_BACKUP/vault-data.tar.gz" -C /var/lib vault/ 2>/dev/null

# Backup credentials
tar -czf "$CURRENT_BACKUP/vault-credentials.tar.gz" -C /root .vault/ 2>/dev/null
chmod 600 "$CURRENT_BACKUP/vault-credentials.tar.gz"

# Backup policies and configurations
if [[ ! -z "$VAULT_TOKEN" ]]; then
    vault policy list -format=json > "$CURRENT_BACKUP/policies.json" 2>/dev/null || true
    vault auth list -format=json > "$CURRENT_BACKUP/auth-methods.json" 2>/dev/null || true
    vault secrets list -format=json > "$CURRENT_BACKUP/secrets-engines.json" 2>/dev/null || true
fi

# Create backup metadata
cat > "$CURRENT_BACKUP/metadata.json" << EOL
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "backup_type": "continuous",
  "vault_version": "$(vault version 2>/dev/null | head -1 || echo 'unknown')",
  "hostname": "$(hostname)",
  "backup_size": "$(du -sh $CURRENT_BACKUP | cut -f1)"
}
EOL

# Clean up old backups
find "$BACKUP_DIR" -type d -mtime +$RETENTION_DAYS -exec rm -rf {} + 2>/dev/null || true

# Create symlink to latest backup
ln -sfn "$CURRENT_BACKUP" "$BACKUP_DIR/latest"

echo "Backup completed: $CURRENT_BACKUP"
EOF

chmod +x /vault/scripts/continuous-backup.sh

# Add to cron for every 15 minutes
echo "*/15 * * * * root /vault/scripts/continuous-backup.sh" >> /etc/crontab
```

#### Backup Validation Script
```bash
cat > /vault/scripts/validate-backup.sh << 'EOF'
#!/bin/bash

BACKUP_PATH="$1"

if [ -z "$BACKUP_PATH" ]; then
    echo "Usage: $0 <backup_path>"
    exit 1
fi

if [ ! -d "$BACKUP_PATH" ]; then
    echo "Backup directory not found: $BACKUP_PATH"
    exit 1
fi

echo "Validating backup: $BACKUP_PATH"

# Check required files
REQUIRED_FILES=(
    "metadata.json"
    "vault-config.tar.gz"
    "vault-data.tar.gz"
    "vault-credentials.tar.gz"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$BACKUP_PATH/$file" ]; then
        echo "✅ $file"
    else
        echo "❌ $file (missing)"
    fi
done

# Validate Raft snapshot if exists
if [ -f "$BACKUP_PATH/vault.snap" ]; then
    echo "✅ vault.snap"
    # Could add snapshot validation here
else
    echo "⚠️ vault.snap (missing - vault may have been sealed)"
fi

# Check backup metadata
if [ -f "$BACKUP_PATH/metadata.json" ]; then
    echo ""
    echo "Backup Information:"
    cat "$BACKUP_PATH/metadata.json" | jq
fi

echo ""
echo "Backup validation completed"
EOF

chmod +x /vault/scripts/validate-backup.sh
```

### Recovery Testing

#### Disaster Recovery Test Script
```bash
cat > /vault/scripts/dr-test.sh << 'EOF'
#!/bin/bash

echo "🧪 DISASTER RECOVERY TEST"
echo "========================"
echo "This script will test disaster recovery procedures"
echo "WARNING: This should only be run on test systems!"
echo ""

read -p "Are you sure you want to continue? (type 'yes'): " -r
if [[ ! $REPLY == "yes" ]]; then
    echo "Test cancelled"
    exit 0
fi

# Create test backup
echo "Creating test backup..."
/vault/scripts/continuous-backup.sh

# Find latest backup
LATEST_BACKUP=$(ls -t /backups/vault/ | head -1)
echo "Using backup: $LATEST_BACKUP"

# Validate backup
echo "Validating backup..."
/vault/scripts/validate-backup.sh "/backups/vault/$LATEST_BACKUP"

# Test restoration process (on test server only)
echo ""
echo "To complete the test:"
echo "1. Deploy a test server"
echo "2. Run the full recovery procedure"
echo "3. Validate all services are working"
echo "4. Document any issues found"

echo ""
echo "DR Test preparation completed"
EOF

chmod +x /vault/scripts/dr-test.sh
```

## 🔄 Recovery Validation

### Post-Recovery Checklist

#### Service Validation
```bash
# Create post-recovery validation script
cat > /vault/scripts/post-recovery-validation.sh << 'EOF'
#!/bin/bash

echo "🔍 POST-RECOVERY VALIDATION"
echo "=========================="

export VAULT_ADDR=${VAULT_ADDR:-https://127.0.0.1:8200}

# 1. Service Status
echo "1. Service Status:"
if systemctl is-active --quiet vault; then
    echo "   ✅ Vault service is running"
else
    echo "   ❌ Vault service is not running"
    exit 1
fi

# 2. Vault Status
echo ""
echo "2. Vault Status:"
if vault status >/dev/null 2>&1; then
    VAULT_STATUS=$(vault status -format=json)
    SEALED=$(echo "$VAULT_STATUS" | jq -r '.sealed')
    
    if [ "$SEALED" = "false" ]; then
        echo "   ✅ Vault is unsealed and accessible"
    else
        echo "   ❌ Vault is sealed"
        exit 1
    fi
else
    echo "   ❌ Vault is not responding"
    exit 1
fi

# 3. Authentication Test
echo ""
echo "3. Authentication Test:"
if [[ -f /root/.vault/root-token ]]; then
    export VAULT_TOKEN=$(cat /root/.vault/root-token)
    if vault auth -method=token token="$VAULT_TOKEN" >/dev/null 2>&1; then
        echo "   ✅ Root token authentication successful"
    else
        echo "   ❌ Root token authentication failed"
        exit 1
    fi
else
    echo "   ❌ Root token file not found"
    exit 1
fi

# 4. Policy Verification
echo ""
echo "4. Policy Verification:"
POLICIES=$(vault policy list 2>/dev/null | wc -l)
if [ "$POLICIES" -gt 0 ]; then
    echo "   ✅ $POLICIES policies found"
    vault policy list
else
    echo "   ⚠️ No policies found"
fi

# 5. Auth Methods
echo ""
echo "5. Authentication Methods:"
vault auth list

# 6. Secrets Engines
echo ""
echo "6. Secrets Engines:"
vault secrets list

# 7. Test Secret Operations
echo ""
echo "7. Secret Operations Test:"
vault kv put secret/recovery-test timestamp="$(date)" status="recovered" >/dev/null 2>&1
if vault kv get secret/recovery-test >/dev/null 2>&1; then
    echo "   ✅ Secret operations working"
    vault kv delete secret/recovery-test >/dev/null 2>&1
else
    echo "   ❌ Secret operations failed"
    exit 1
fi

echo ""
echo "✅ POST-RECOVERY VALIDATION SUCCESSFUL"
echo "All systems are operational"
EOF

chmod +x /vault/scripts/post-recovery-validation.sh
```

## 📞 Communication Plan

### Incident Communication Template

#### Initial Alert Template
```
🚨 VAULT INCIDENT ALERT

Incident ID: VAULT-[YYYYMMDD]-[HHMM]
Severity: [CRITICAL/HIGH/MEDIUM/LOW]
Status: [INVESTIGATING/IN PROGRESS/RESOLVED]

Issue Summary:
[Brief description of the issue]

Impact:
[Description of services/applications affected]

Actions Taken:
[What has been done so far]

Next Steps:
[What will be done next]

ETA for Resolution:
[Expected time to resolution]

Point of Contact:
[Name and contact information]

Last Updated: [Timestamp]
```

#### Resolution Notification Template
```
✅ VAULT INCIDENT RESOLVED

Incident ID: VAULT-[YYYYMMDD]-[HHMM]
Status: RESOLVED
Resolution Time: [Duration]

Root Cause:
[Brief explanation of what caused the issue]

Resolution:
[What was done to fix the issue]

Preventive Measures:
[What will be done to prevent recurrence]

Post-Incident Actions:
[Any follow-up tasks required]

Incident Commander: [Name]
Resolution Time: [Timestamp]
```

### Stakeholder Notification List

#### Internal Notifications
- Development Teams
- Operations Team
- Security Team  
- Management
- Customer Support

#### External Notifications
- Customers (if public-facing)
- Partners/Vendors
- Compliance Teams
- External Auditors

## 📚 Runbooks Quick Reference

### Emergency Command Reference
```bash
# Service Control
systemctl status vault
systemctl restart vault
systemctl stop vault
systemctl start vault

# Vault Operations
vault status
vault operator unseal [KEY]
vault login [TOKEN]
vault operator raft snapshot save [FILE]
vault operator raft snapshot restore [FILE]

# Emergency Access
sudo cat /root/.vault/root-token
sudo jq -r '.unseal_keys_b64[0]' /opt/vault/init.json

# Backup Operations
/vault/scripts/continuous-backup.sh
ls -la /backups/vault/
/vault/scripts/validate-backup.sh [PATH]

# Validation
/vault/scripts/post-recovery-validation.sh
/vault/scripts/status-dashboard.sh
```

---

## ⚠️ IMPORTANT REMINDERS

1. **Test Recovery Procedures Regularly**: Run DR tests monthly
2. **Keep Backups Current**: Automated backups every 15 minutes
3. **Secure Key Storage**: Unseal keys must be distributed and secure
4. **Document All Actions**: Log all emergency actions taken
5. **Validate After Recovery**: Always run post-recovery validation
6. **Communicate Status**: Keep stakeholders informed during incidents

**🎯 Recovery success depends on preparation, practice, and clear procedures!**

---
*Last Updated: $(date)*
*Disaster Recovery Plan Version: 1.0*