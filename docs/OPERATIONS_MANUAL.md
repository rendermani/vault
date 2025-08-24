# 📖 Vault Operations Manual

## 🎯 Daily Operations

### Morning Checklist (5 minutes)
```bash
# Run daily status check
/vault/scripts/status-dashboard.sh

# Check overnight alerts
tail -20 /var/log/vault-alerts.log

# Verify last night's backup
ls -la /backups/vault/ | head -5

# Quick health validation
export VAULT_ADDR=https://127.0.0.1:8200
vault status
```

### System Health Verification
```bash
#!/bin/bash
# Save as /vault/scripts/daily-health-check.sh

echo "🏥 DAILY HEALTH CHECK - $(date)"
echo "================================"

# 1. Service Status
echo "1. Service Status:"
if systemctl is-active --quiet vault; then
    echo "   ✅ Vault service running"
    UPTIME=$(systemctl show vault --property=ActiveEnterTimestamp | cut -d= -f2)
    echo "   Started: $UPTIME"
else
    echo "   ❌ Vault service not running!"
    exit 1
fi

# 2. Vault Accessibility
echo ""
echo "2. Vault Accessibility:"
export VAULT_ADDR=${VAULT_ADDR:-https://127.0.0.1:8200}
if curl -f -s --max-time 10 "$VAULT_ADDR/v1/sys/health" >/dev/null; then
    echo "   ✅ Vault API responding"
    
    # Check seal status
    SEALED=$(vault status -format=json 2>/dev/null | jq -r '.sealed')
    if [ "$SEALED" = "false" ]; then
        echo "   ✅ Vault unsealed"
    else
        echo "   🔒 Vault sealed - requires attention!"
    fi
else
    echo "   ❌ Vault API not responding!"
fi

# 3. Resource Usage
echo ""
echo "3. Resource Usage:"
MEMORY_PCT=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
DISK_PCT=$(df /var/lib/vault 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || df / | tail -1 | awk '{print $5}' | sed 's/%//')

echo "   Memory: ${MEMORY_PCT}%"
echo "   Disk: ${DISK_PCT}%"

if (( $(echo "$MEMORY_PCT > 85" | bc -l) )); then
    echo "   ⚠️ High memory usage!"
fi

if [ "$DISK_PCT" -gt 85 ]; then
    echo "   ⚠️ High disk usage!"
fi

# 4. Recent Activity
echo ""
echo "4. Recent Activity (last hour):"
if [ -f "/var/log/vault/audit.log" ]; then
    HOUR_AGO=$(date -d '1 hour ago' +%s)
    REQUESTS=$(tail -1000 /var/log/vault/audit.log | \
        jq -r --arg hour_ago "$HOUR_AGO" \
        'select(.time | tonumber > ($hour_ago | tonumber)) | .type' | \
        wc -l)
    echo "   Requests: $REQUESTS"
    
    UNIQUE_CLIENTS=$(tail -1000 /var/log/vault/audit.log | \
        jq -r --arg hour_ago "$HOUR_AGO" \
        'select(.time | tonumber > ($hour_ago | tonumber)) | .request.remote_address' | \
        sort | uniq | wc -l)
    echo "   Unique clients: $UNIQUE_CLIENTS"
else
    echo "   ⚠️ Audit log not found"
fi

echo ""
echo "Daily health check completed ✅"
```

## 🔧 Routine Maintenance Tasks

### Weekly Maintenance (30 minutes)

#### Log Rotation and Cleanup
```bash
#!/bin/bash
# Weekly maintenance script

echo "🔄 WEEKLY MAINTENANCE - $(date)"
echo "==============================="

# 1. Rotate logs if needed
echo "1. Log Rotation:"
if [ -f "/var/log/vault/vault.log" ]; then
    LOG_SIZE=$(du -m /var/log/vault/vault.log | cut -f1)
    echo "   Current log size: ${LOG_SIZE}MB"
    
    if [ "$LOG_SIZE" -gt 100 ]; then
        echo "   Rotating large log file..."
        systemctl reload vault
    fi
fi

# 2. Clean old backups
echo ""
echo "2. Backup Cleanup:"
BACKUP_COUNT_BEFORE=$(ls /backups/vault/ | wc -l)
find /backups/vault -type d -mtime +30 -exec rm -rf {} + 2>/dev/null || true
BACKUP_COUNT_AFTER=$(ls /backups/vault/ | wc -l)
echo "   Removed $((BACKUP_COUNT_BEFORE - BACKUP_COUNT_AFTER)) old backups"
echo "   Current backup count: $BACKUP_COUNT_AFTER"

# 3. Security token cleanup
echo ""
echo "3. Token Cleanup:"
if [ -x "/vault/security/secure-token-manager.sh" ]; then
    /vault/security/secure-token-manager.sh cleanup
    /vault/security/secure-token-manager.sh monitor
fi

# 4. System updates check
echo ""
echo "4. System Updates:"
if command -v apt >/dev/null; then
    UPDATES=$(apt list --upgradable 2>/dev/null | wc -l)
    echo "   Available updates: $UPDATES"
fi

# 5. Certificate expiration check
echo ""
echo "5. Certificate Check:"
if [ -f "/etc/vault.d/tls/vault-cert.pem" ]; then
    CERT_EXPIRY=$(openssl x509 -in /etc/vault.d/tls/vault-cert.pem -noout -dates | grep notAfter | cut -d= -f2)
    DAYS_LEFT=$(( ($(date -d "$CERT_EXPIRY" +%s) - $(date +%s)) / 86400 ))
    echo "   Certificate expires in: $DAYS_LEFT days"
    
    if [ "$DAYS_LEFT" -lt 30 ]; then
        echo "   ⚠️ Certificate renewal needed soon!"
    fi
fi

echo ""
echo "Weekly maintenance completed ✅"
```

### Monthly Tasks

#### Performance Review
```bash
#!/bin/bash
# Monthly performance review

echo "📊 MONTHLY PERFORMANCE REVIEW - $(date)"
echo "======================================="

# 1. Storage Growth Analysis
echo "1. Storage Growth:"
VAULT_SIZE=$(du -sh /var/lib/vault | cut -f1)
echo "   Current Vault data: $VAULT_SIZE"

# 2. Usage Statistics
echo ""
echo "2. Usage Statistics (last 30 days):"
if [ -f "/var/log/vault/audit.log" ]; then
    # This would be more sophisticated in real implementation
    TOTAL_REQUESTS=$(wc -l < /var/log/vault/audit.log)
    echo "   Total requests in log: $TOTAL_REQUESTS"
fi

# 3. Performance Metrics
echo ""
echo "3. Performance Metrics:"
echo "   Average response time: [Would implement with monitoring tools]"
echo "   Peak concurrent users: [Would implement with monitoring tools]"
echo "   Error rate: [Would implement with monitoring tools]"

# 4. Security Review
echo ""
echo "4. Security Events:"
if [ -f "/var/log/vault-security-alerts.log" ]; then
    SECURITY_EVENTS=$(wc -l < /var/log/vault-security-alerts.log)
    echo "   Security alerts this month: $SECURITY_EVENTS"
    
    if [ "$SECURITY_EVENTS" -gt 0 ]; then
        echo "   Recent security events:"
        tail -5 /var/log/vault-security-alerts.log
    fi
fi

echo ""
echo "Monthly review completed ✅"
```

## 🔍 Troubleshooting Guide

### Common Issues and Solutions

#### Issue 1: Vault Service Won't Start

**Symptoms:**
- `systemctl status vault` shows failed
- Error in system logs
- Service starts then immediately stops

**Diagnostic Steps:**
```bash
# 1. Check configuration
vault server -config=/etc/vault.d/vault.hcl -test

# 2. Check file permissions
ls -la /etc/vault.d/vault.hcl
ls -la /var/lib/vault/

# 3. Check system resources
df -h /var/lib/vault
free -h

# 4. Check detailed logs
journalctl -u vault -n 50
tail -50 /var/log/vault/vault.log
```

**Common Solutions:**
```bash
# Fix permissions
chown vault:vault /etc/vault.d/vault.hcl
chown -R vault:vault /var/lib/vault/
chmod 640 /etc/vault.d/vault.hcl

# Fix disk space
# Clean up logs or expand storage

# Fix configuration
# Restore from backup or fix syntax errors

# Restart service
systemctl restart vault
```

#### Issue 2: High Memory Usage

**Symptoms:**
- System running slow
- Out of memory errors
- Performance degradation

**Diagnostic Steps:**
```bash
# Check memory usage
free -h
top -p $(pgrep vault)

# Check Vault cache
vault read sys/config/cache

# Check concurrent sessions
ps aux | grep vault | wc -l
```

**Solutions:**
```bash
# Restart Vault (clears cache)
systemctl restart vault

# Tune cache settings (if configured)
vault write sys/config/cache size=65536

# Add more memory or reduce other services
```

#### Issue 3: Certificate Errors

**Symptoms:**
- TLS handshake failures
- Certificate expired errors
- Unable to connect via HTTPS

**Diagnostic Steps:**
```bash
# Check certificate validity
openssl x509 -in /etc/vault.d/tls/vault-cert.pem -noout -dates

# Test TLS connection
openssl s_client -connect localhost:8200

# Check certificate chain
openssl verify -CAfile /etc/vault.d/tls/ca-cert.pem /etc/vault.d/tls/vault-cert.pem
```

**Solutions:**
```bash
# Renew certificates
/vault/security/tls-cert-manager.sh renew

# Update configuration if needed
systemctl restart vault
```

### Performance Optimization

#### Memory Optimization
```bash
# Check current memory allocation
ps -o pid,rss,cmd -p $(pgrep vault)

# Monitor memory growth
while true; do
    echo "$(date): $(ps -o rss --no-headers -p $(pgrep vault))KB"
    sleep 60
done
```

#### Disk I/O Optimization
```bash
# Check I/O statistics
iostat -x 1 5

# Monitor Vault storage
du -sh /var/lib/vault/*

# Check for disk bottlenecks
iotop -p $(pgrep vault)
```

## 🔐 Security Operations

### Access Management

#### Token Lifecycle Management
```bash
#!/bin/bash
# Token lifecycle management

echo "🔑 TOKEN LIFECYCLE MANAGEMENT"
echo "============================"

export VAULT_ADDR=${VAULT_ADDR:-https://127.0.0.1:8200}
export VAULT_TOKEN=$(cat /root/.vault/root-token 2>/dev/null || echo "")

if [ -z "$VAULT_TOKEN" ]; then
    echo "❌ Root token not available"
    exit 1
fi

# 1. List active tokens
echo "1. Active Tokens:"
vault list auth/token/accessors | head -10

# 2. Check token usage
echo ""
echo "2. Token Statistics:"
TOKEN_COUNT=$(vault list -format=json auth/token/accessors 2>/dev/null | jq '. | length')
echo "   Total active tokens: $TOKEN_COUNT"

# 3. Identify old tokens (would need more sophisticated implementation)
echo ""
echo "3. Token Cleanup Candidates:"
echo "   [Would implement with token metadata analysis]"

# 4. AppRole status
echo ""
echo "4. AppRole Status:"
if vault auth list | grep -q approle; then
    vault list auth/approle/role
else
    echo "   AppRole not enabled"
fi

echo ""
echo "Token management review completed ✅"
```

#### Policy Management
```bash
#!/bin/bash
# Policy management operations

echo "📋 POLICY MANAGEMENT"
echo "=================="

export VAULT_ADDR=${VAULT_ADDR:-https://127.0.0.1:8200}
export VAULT_TOKEN=$(cat /root/.vault/root-token 2>/dev/null || echo "")

# 1. List all policies
echo "1. Current Policies:"
vault policy list

# 2. Policy validation
echo ""
echo "2. Policy Validation:"
for policy in $(vault policy list | grep -v root | grep -v default); do
    echo "   Checking policy: $policy"
    if vault policy read "$policy" >/dev/null 2>&1; then
        echo "     ✅ Valid"
    else
        echo "     ❌ Invalid or missing"
    fi
done

# 3. Unused policy detection
echo ""
echo "3. Policy Usage Analysis:"
echo "   [Would implement with audit log analysis]"

echo ""
echo "Policy management completed ✅"
```

### Audit and Compliance

#### Audit Log Analysis
```bash
#!/bin/bash
# Audit log analysis

echo "📊 AUDIT LOG ANALYSIS"
echo "===================="

AUDIT_LOG="/var/log/vault/audit.log"

if [ ! -f "$AUDIT_LOG" ]; then
    echo "❌ Audit log not found: $AUDIT_LOG"
    exit 1
fi

# 1. Log Statistics
echo "1. Log Statistics:"
TOTAL_EVENTS=$(wc -l < "$AUDIT_LOG")
echo "   Total events: $TOTAL_EVENTS"

LOG_SIZE=$(du -h "$AUDIT_LOG" | cut -f1)
echo "   Log file size: $LOG_SIZE"

# 2. Request Types Analysis
echo ""
echo "2. Request Types (last 1000 events):"
tail -1000 "$AUDIT_LOG" | jq -r '.type' | sort | uniq -c | sort -nr | head -10

# 3. Top Clients
echo ""
echo "3. Top Clients (last 1000 events):"
tail -1000 "$AUDIT_LOG" | jq -r '.request.remote_address // "unknown"' | sort | uniq -c | sort -nr | head -10

# 4. Failed Requests
echo ""
echo "4. Failed Requests (last 24 hours):"
YESTERDAY=$(date -d '24 hours ago' +%s)
tail -1000 "$AUDIT_LOG" | jq -r --arg yesterday "$YESTERDAY" \
    'select(.time | tonumber > ($yesterday | tonumber)) | select(.error != null) | .error' | \
    sort | uniq -c | sort -nr

# 5. Authentication Events
echo ""
echo "5. Authentication Events (last 24 hours):"
tail -1000 "$AUDIT_LOG" | jq -r --arg yesterday "$YESTERDAY" \
    'select(.time | tonumber > ($yesterday | tonumber)) | select(.request.path | test("auth/")) | .request.path' | \
    sort | uniq -c | sort -nr

echo ""
echo "Audit analysis completed ✅"
```

## 📈 Monitoring and Alerting

### Key Performance Indicators (KPIs)

#### System KPIs
- **Uptime**: Target 99.9%
- **Response Time**: < 100ms for health checks
- **Memory Usage**: < 80% of available RAM
- **Disk Usage**: < 85% of available storage
- **CPU Usage**: < 70% average

#### Security KPIs
- **Failed Authentication Rate**: < 1% of total requests
- **Token Rotation Frequency**: Every 90 days for root token
- **Certificate Renewal**: 30 days before expiration
- **Audit Log Coverage**: 100% of requests logged

### Monitoring Scripts

#### Real-time Monitoring
```bash
#!/bin/bash
# Real-time monitoring dashboard

while true; do
    clear
    echo "⚡ VAULT REAL-TIME MONITOR"
    echo "========================"
    echo "Updated: $(date)"
    echo ""
    
    # System Status
    echo "🖥️  SYSTEM:"
    echo "   CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')%"
    echo "   Memory: $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')"
    echo "   Disk: $(df /var/lib/vault 2>/dev/null | tail -1 | awk '{print $5}' || echo "N/A")"
    
    # Vault Status
    echo ""
    echo "🏛️  VAULT:"
    export VAULT_ADDR=${VAULT_ADDR:-https://127.0.0.1:8200}
    if vault status >/dev/null 2>&1; then
        VAULT_STATUS=$(vault status -format=json)
        SEALED=$(echo "$VAULT_STATUS" | jq -r '.sealed')
        VERSION=$(echo "$VAULT_STATUS" | jq -r '.version')
        
        if [ "$SEALED" = "false" ]; then
            echo "   Status: ✅ UNSEALED"
        else
            echo "   Status: 🔒 SEALED"
        fi
        echo "   Version: $VERSION"
    else
        echo "   Status: ❌ UNREACHABLE"
    fi
    
    # Recent Activity
    echo ""
    echo "📊 ACTIVITY (last 5 minutes):"
    if [ -f "/var/log/vault/audit.log" ]; then
        FIVE_MIN_AGO=$(date -d '5 minutes ago' +%s)
        RECENT_REQUESTS=$(tail -500 /var/log/vault/audit.log | \
            jq -r --arg five_min_ago "$FIVE_MIN_AGO" \
            'select(.time | tonumber > ($five_min_ago | tonumber))' | wc -l)
        echo "   Requests: $RECENT_REQUESTS"
    else
        echo "   No audit data available"
    fi
    
    echo ""
    echo "Press Ctrl+C to exit..."
    sleep 5
done
```

## 🔄 Backup and Recovery Operations

### Backup Verification
```bash
#!/bin/bash
# Backup verification script

echo "💾 BACKUP VERIFICATION"
echo "====================="

BACKUP_DIR="/backups/vault"

if [ ! -d "$BACKUP_DIR" ]; then
    echo "❌ Backup directory not found: $BACKUP_DIR"
    exit 1
fi

# 1. List recent backups
echo "1. Recent Backups:"
ls -lt "$BACKUP_DIR" | head -5

# 2. Verify latest backup integrity
echo ""
echo "2. Latest Backup Verification:"
LATEST_BACKUP=$(ls -t "$BACKUP_DIR" | head -1)
if [ -n "$LATEST_BACKUP" ]; then
    echo "   Verifying: $LATEST_BACKUP"
    /vault/scripts/validate-backup.sh "$BACKUP_DIR/$LATEST_BACKUP"
else
    echo "   ❌ No backups found"
fi

# 3. Backup size analysis
echo ""
echo "3. Backup Size Trend:"
for backup in $(ls -t "$BACKUP_DIR" | head -5); do
    SIZE=$(du -sh "$BACKUP_DIR/$backup" 2>/dev/null | cut -f1)
    echo "   $backup: $SIZE"
done

echo ""
echo "Backup verification completed ✅"
```

## 📋 Operational Checklists

### Pre-Maintenance Checklist
- [ ] Notify stakeholders of planned maintenance
- [ ] Create current backup
- [ ] Verify backup integrity
- [ ] Document current system state
- [ ] Prepare rollback plan
- [ ] Test all procedures in staging environment

### Post-Maintenance Checklist
- [ ] Verify Vault service is running
- [ ] Confirm Vault is unsealed and responsive
- [ ] Test authentication methods
- [ ] Verify applications can connect
- [ ] Check monitoring and alerting
- [ ] Update documentation if needed
- [ ] Notify stakeholders of completion

### Emergency Response Checklist
- [ ] Identify the issue and severity
- [ ] Notify incident commander
- [ ] Create incident ticket/communication
- [ ] Implement immediate containment
- [ ] Execute recovery procedures
- [ ] Validate system restoration
- [ ] Document incident and lessons learned
- [ ] Conduct post-incident review

## 🎓 Training and Knowledge Transfer

### New Administrator Onboarding
1. **Day 1**: System overview and access setup
2. **Day 2**: Daily operations and monitoring
3. **Day 3**: Security procedures and policies
4. **Day 4**: Troubleshooting and emergency procedures
5. **Day 5**: Backup/recovery and hands-on practice

### Knowledge Base Maintenance
- Update procedures after each incident
- Document new configurations and changes
- Maintain vendor contact information
- Keep emergency procedures current
- Review and update quarterly

---

## 📞 Quick Reference

### Essential Commands
```bash
# Service Management
systemctl status vault
systemctl restart vault

# Vault Operations  
vault status
vault operator unseal
vault login

# Monitoring
/vault/scripts/status-dashboard.sh
tail -f /var/log/vault/audit.log

# Backup
/vault/scripts/continuous-backup.sh
ls -la /backups/vault/

# Emergency Access
sudo cat /root/.vault/root-token
sudo jq -r '.unseal_keys_b64[0]' /opt/vault/init.json
```

### Key File Locations
- **Configuration**: `/etc/vault.d/vault.hcl`
- **Data**: `/var/lib/vault/`
- **Logs**: `/var/log/vault/`
- **Backups**: `/backups/vault/`
- **Scripts**: `/vault/scripts/`
- **Security Tools**: `/vault/security/`

---

**📖 This operations manual provides comprehensive guidance for day-to-day Vault management and maintenance.**

*Keep this manual updated and refer to it regularly for consistent operations.*

---
*Last Updated: $(date)*
*Operations Manual Version: 1.0*