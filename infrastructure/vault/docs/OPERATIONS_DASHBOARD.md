# 📊 Vault Operations Dashboard

## 🚀 Quick Status Overview

### System Health Check
```bash
#!/bin/bash
# Quick health dashboard - save as /vault/scripts/status-dashboard.sh

echo "=================================================="
echo "🔐 VAULT OPERATIONS DASHBOARD"
echo "=================================================="
echo "Timestamp: $(date)"
echo ""

# Vault Service Status
echo "🔧 SERVICE STATUS:"
if systemctl is-active --quiet vault; then
    echo "✅ Vault Service: RUNNING"
else
    echo "❌ Vault Service: STOPPED"
fi

# Vault Status
export VAULT_ADDR=${VAULT_ADDR:-https://127.0.0.1:8200}
echo ""
echo "🏛️ VAULT STATUS:"
if vault status &>/dev/null; then
    VAULT_STATUS=$(vault status -format=json)
    INITIALIZED=$(echo "$VAULT_STATUS" | jq -r '.initialized')
    SEALED=$(echo "$VAULT_STATUS" | jq -r '.sealed')
    VERSION=$(echo "$VAULT_STATUS" | jq -r '.version')
    
    if [ "$INITIALIZED" = "true" ] && [ "$SEALED" = "false" ]; then
        echo "✅ Vault Status: READY"
    elif [ "$SEALED" = "true" ]; then
        echo "🔒 Vault Status: SEALED"
    else
        echo "⚠️ Vault Status: NOT INITIALIZED"
    fi
    
    echo "   Version: $VERSION"
    echo "   Initialized: $INITIALIZED"
    echo "   Sealed: $SEALED"
else
    echo "❌ Vault Status: UNREACHABLE"
fi

# System Resources
echo ""
echo "💻 SYSTEM RESOURCES:"
MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
DISK_USAGE=$(df /var/lib/vault 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || df / | tail -1 | awk '{print $5}' | sed 's/%//')
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')

echo "   Memory Usage: ${MEMORY_USAGE}%"
echo "   Disk Usage: ${DISK_USAGE}%"
echo "   CPU Usage: ${CPU_USAGE}%"

# Recent Backups
echo ""
echo "💾 BACKUP STATUS:"
if [ -d "/backups/vault" ]; then
    LATEST_BACKUP=$(ls -t /backups/vault/ | head -1)
    BACKUP_COUNT=$(ls /backups/vault/ | wc -l)
    if [ -n "$LATEST_BACKUP" ]; then
        echo "✅ Latest Backup: $LATEST_BACKUP"
        echo "   Total Backups: $BACKUP_COUNT"
    else
        echo "⚠️ No backups found"
    fi
else
    echo "❌ Backup directory not found"
fi

# Security Status
echo ""
echo "🛡️ SECURITY STATUS:"
if [ -f "/var/log/vault/audit.log" ]; then
    AUDIT_SIZE=$(du -h /var/log/vault/audit.log | cut -f1)
    echo "✅ Audit Logging: ENABLED ($AUDIT_SIZE)"
else
    echo "⚠️ Audit Logging: NOT CONFIGURED"
fi

if ps aux | grep -q "[s]ecurity-monitor.sh"; then
    echo "✅ Security Monitor: RUNNING"
else
    echo "⚠️ Security Monitor: NOT RUNNING"
fi

echo "=================================================="
```

## 📈 Monitoring Setup

### Health Check Endpoints

#### Primary Health Check
```bash
# Basic health check
curl -s https://127.0.0.1:8200/v1/sys/health | jq

# Expected healthy response:
{
  "initialized": true,
  "sealed": false,
  "standby": false,
  "performance_standby": false,
  "replication_performance_mode": "disabled",
  "replication_dr_mode": "disabled",
  "server_time_utc": 1234567890,
  "version": "1.17.3",
  "cluster_name": "vault-prod",
  "cluster_id": "abc-123-def"
}
```

#### Detailed System Status
```bash
# Comprehensive status check
cat > /vault/scripts/detailed-status.sh << 'EOF'
#!/bin/bash

export VAULT_ADDR=${VAULT_ADDR:-https://127.0.0.1:8200}
export VAULT_TOKEN=$(cat /root/.vault/root-token 2>/dev/null || echo "")

echo "=== VAULT DETAILED STATUS ==="
echo "Timestamp: $(date)"
echo ""

# System Health
echo "📊 SYSTEM METRICS:"
vault read sys/health
echo ""

# Storage Backend
echo "💾 STORAGE STATUS:"
vault read sys/storage/raft/configuration
echo ""

# Authentication Methods
echo "🔐 AUTH METHODS:"
vault auth list
echo ""

# Secrets Engines
echo "🗝️ SECRETS ENGINES:"
vault secrets list
echo ""

# Policies
echo "📋 POLICIES:"
vault policy list
echo ""

# Recent Audit Events (last 10)
echo "📝 RECENT AUDIT EVENTS:"
if [ -f "/var/log/vault/audit.log" ]; then
    tail -10 /var/log/vault/audit.log | jq -r '.time + " " + .type + " " + (.request.path // "N/A")'
else
    echo "Audit log not found"
fi

echo ""
echo "=== STATUS COMPLETE ==="
EOF

chmod +x /vault/scripts/detailed-status.sh
```

### Performance Metrics

#### Prometheus Metrics
```bash
# Enable Prometheus metrics endpoint
curl -s https://127.0.0.1:8200/v1/sys/metrics?format=prometheus

# Key metrics to monitor:
# - vault_core_unsealed: Vault seal status
# - vault_runtime_alloc_bytes: Memory usage
# - vault_runtime_num_goroutines: Active goroutines
# - vault_token_creation_total: Token creation rate
# - vault_audit_log_request_total: Audit log requests
```

#### Custom Metrics Collection
```bash
# Create metrics collector script
cat > /vault/scripts/collect-metrics.sh << 'EOF'
#!/bin/bash

METRICS_FILE="/tmp/vault-metrics-$(date +%s).json"
export VAULT_ADDR=${VAULT_ADDR:-https://127.0.0.1:8200}

# Collect system metrics
{
    echo "{"
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"system\": {"
    echo "    \"memory_usage\": $(free | grep Mem | awk '{printf "%.2f", $3/$2 * 100.0}'),"
    echo "    \"disk_usage\": $(df /var/lib/vault | tail -1 | awk '{print $5}' | sed 's/%//'),"
    echo "    \"cpu_usage\": $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')"
    echo "  },"
    
    # Vault-specific metrics
    if vault status &>/dev/null; then
        VAULT_STATUS=$(vault status -format=json)
        echo "  \"vault\": $VAULT_STATUS,"
    fi
    
    echo "  \"collected\": true"
    echo "}"
} > "$METRICS_FILE"

echo "Metrics collected: $METRICS_FILE"
EOF

chmod +x /vault/scripts/collect-metrics.sh
```

## 🔔 Alert Configuration

### System Alerts

#### Disk Space Alert
```bash
# Create disk space monitor
cat > /vault/scripts/disk-space-alert.sh << 'EOF'
#!/bin/bash

THRESHOLD=85
VAULT_DISK_USAGE=$(df /var/lib/vault | tail -1 | awk '{print $5}' | sed 's/%//')

if [ "$VAULT_DISK_USAGE" -gt "$THRESHOLD" ]; then
    echo "🚨 CRITICAL: Vault disk usage at ${VAULT_DISK_USAGE}% (threshold: ${THRESHOLD}%)"
    
    # Send alert (customize for your notification system)
    # Example: Send email, Slack message, etc.
    echo "Alert: Vault disk usage critical" | mail -s "Vault Disk Alert" admin@company.com
    
    # Log the alert
    echo "$(date): Disk usage alert - ${VAULT_DISK_USAGE}%" >> /var/log/vault-alerts.log
fi
EOF

chmod +x /vault/scripts/disk-space-alert.sh

# Add to cron for regular checking
echo "*/15 * * * * root /vault/scripts/disk-space-alert.sh" >> /etc/crontab
```

#### Service Status Alert
```bash
# Create service monitor
cat > /vault/scripts/service-monitor.sh << 'EOF'
#!/bin/bash

ALERT_LOG="/var/log/vault-alerts.log"

check_service() {
    SERVICE=$1
    if ! systemctl is-active --quiet "$SERVICE"; then
        echo "🚨 CRITICAL: $SERVICE is not running!" | tee -a "$ALERT_LOG"
        
        # Attempt to restart
        systemctl start "$SERVICE"
        sleep 5
        
        if systemctl is-active --quiet "$SERVICE"; then
            echo "✅ SUCCESS: $SERVICE restarted successfully" | tee -a "$ALERT_LOG"
        else
            echo "❌ FAILED: Could not restart $SERVICE" | tee -a "$ALERT_LOG"
            # Send critical alert
        fi
    fi
}

# Monitor critical services
check_service "vault"

# Check Vault accessibility
export VAULT_ADDR=${VAULT_ADDR:-https://127.0.0.1:8200}
if ! curl -f -s --max-time 10 "$VAULT_ADDR/v1/sys/health" >/dev/null; then
    echo "🚨 CRITICAL: Vault health endpoint not responding!" | tee -a "$ALERT_LOG"
fi

# Check if Vault is sealed
if vault status 2>/dev/null | grep -q "Sealed.*true"; then
    echo "🔒 WARNING: Vault is sealed!" | tee -a "$ALERT_LOG"
fi
EOF

chmod +x /vault/scripts/service-monitor.sh

# Add to cron for regular monitoring
echo "*/5 * * * * root /vault/scripts/service-monitor.sh" >> /etc/crontab
```

### Security Alerts

#### Failed Authentication Monitor
```bash
# Create security alert monitor
cat > /vault/scripts/security-alerts.sh << 'EOF'
#!/bin/bash

AUDIT_LOG="/var/log/vault/audit.log"
ALERT_LOG="/var/log/vault-security-alerts.log"
THRESHOLD=5  # Failed attempts in last 5 minutes

if [ -f "$AUDIT_LOG" ]; then
    # Count failed auth attempts in last 5 minutes
    FAILED_ATTEMPTS=$(tail -1000 "$AUDIT_LOG" | \
        jq -r 'select(.type == "request" and .error != null and .request.path | test("auth/")) | .time' | \
        awk -v threshold=$(date -d '5 minutes ago' +%s) '$1 > threshold' | wc -l)
    
    if [ "$FAILED_ATTEMPTS" -gt "$THRESHOLD" ]; then
        echo "🚨 SECURITY ALERT: $FAILED_ATTEMPTS failed authentication attempts in last 5 minutes" | tee -a "$ALERT_LOG"
    fi
    
    # Check for unusual access patterns
    UNIQUE_IPS=$(tail -1000 "$AUDIT_LOG" | \
        jq -r '.request.remote_address // "unknown"' | \
        grep -v "127.0.0.1" | sort | uniq | wc -l)
    
    if [ "$UNIQUE_IPS" -gt 10 ]; then
        echo "⚠️ SECURITY NOTICE: Access from $UNIQUE_IPS unique IP addresses" | tee -a "$ALERT_LOG"
    fi
fi
EOF

chmod +x /vault/scripts/security-alerts.sh

# Add to cron for security monitoring
echo "*/5 * * * * root /vault/scripts/security-alerts.sh" >> /etc/crontab
```

## 📊 Performance Dashboard

### Real-time Performance Monitor
```bash
# Create performance dashboard
cat > /vault/scripts/performance-dashboard.sh << 'EOF'
#!/bin/bash

export VAULT_ADDR=${VAULT_ADDR:-https://127.0.0.1:8200}

while true; do
    clear
    echo "════════════════════════════════════════════════"
    echo "🚀 VAULT PERFORMANCE DASHBOARD"
    echo "════════════════════════════════════════════════"
    echo "Updated: $(date)"
    echo ""
    
    # System Performance
    echo "💻 SYSTEM PERFORMANCE:"
    echo "   CPU Usage:    $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')"
    echo "   Memory Usage: $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')"
    echo "   Load Average: $(uptime | awk -F'load average:' '{print $2}')"
    echo ""
    
    # Vault Metrics
    if curl -s --max-time 5 "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
        echo "🔐 VAULT METRICS:"
        
        # Token operations (from audit log)
        if [ -f "/var/log/vault/audit.log" ]; then
            TOKEN_OPS=$(tail -100 /var/log/vault/audit.log | grep -c "auth/token")
            echo "   Recent Token Ops: $TOKEN_OPS"
        fi
        
        # Secret operations
        if [ -f "/var/log/vault/audit.log" ]; then
            SECRET_OPS=$(tail -100 /var/log/vault/audit.log | grep -c "secret/")
            echo "   Recent Secret Ops: $SECRET_OPS"
        fi
        
        # Response times (sample)
        RESPONSE_TIME=$(curl -w "%{time_total}" -s --max-time 5 "$VAULT_ADDR/v1/sys/health" -o /dev/null 2>/dev/null || echo "timeout")
        echo "   Health Check Time: ${RESPONSE_TIME}s"
    else
        echo "❌ VAULT UNREACHABLE"
    fi
    
    echo ""
    echo "Press Ctrl+C to exit..."
    sleep 5
done
EOF

chmod +x /vault/scripts/performance-dashboard.sh
```

## 📱 Mobile/Remote Monitoring

### Status Check via API
```bash
# Create API status endpoint
cat > /vault/scripts/api-status.sh << 'EOF'
#!/bin/bash

export VAULT_ADDR=${VAULT_ADDR:-https://127.0.0.1:8200}

# Create JSON status response
{
    echo "{"
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    
    # Service status
    if systemctl is-active --quiet vault; then
        echo "  \"service_status\": \"running\","
    else
        echo "  \"service_status\": \"stopped\","
    fi
    
    # Vault status
    if vault status &>/dev/null; then
        VAULT_STATUS=$(vault status -format=json)
        echo "  \"vault_status\": $VAULT_STATUS,"
    else
        echo "  \"vault_status\": null,"
    fi
    
    # System metrics
    echo "  \"system\": {"
    echo "    \"memory_usage\": $(free | grep Mem | awk '{printf "%.2f", $3/$2 * 100.0}'),"
    echo "    \"disk_usage\": $(df /var/lib/vault 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo '0'),"
    echo "    \"uptime\": \"$(uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')\""
    echo "  },"
    
    echo "  \"status\": \"ok\""
    echo "}"
} | jq .
EOF

chmod +x /vault/scripts/api-status.sh
```

## 🔧 Automated Maintenance

### Daily Health Report
```bash
# Create daily report generator
cat > /vault/scripts/daily-report.sh << 'EOF'
#!/bin/bash

REPORT_DATE=$(date +%Y-%m-%d)
REPORT_FILE="/var/log/vault-daily-report-$REPORT_DATE.log"

{
    echo "=================================================="
    echo "VAULT DAILY HEALTH REPORT - $REPORT_DATE"
    echo "=================================================="
    echo ""
    
    # Run comprehensive status check
    /vault/scripts/status-dashboard.sh
    echo ""
    
    # Storage usage trend
    echo "📈 STORAGE TREND (Last 7 Days):"
    for i in {6..0}; do
        DATE=$(date -d "$i days ago" +%Y-%m-%d)
        # Would typically pull from historical data
        echo "   $DATE: Historical data would go here"
    done
    echo ""
    
    # Security summary
    echo "🛡️ SECURITY SUMMARY:"
    if [ -f "/var/log/vault/audit.log" ]; then
        echo "   Total requests today: $(grep "$(date +%Y-%m-%d)" /var/log/vault/audit.log | wc -l)"
        echo "   Unique clients: $(grep "$(date +%Y-%m-%d)" /var/log/vault/audit.log | jq -r '.request.remote_address' | sort | uniq | wc -l)"
    fi
    echo ""
    
    # Backup status
    echo "💾 BACKUP STATUS:"
    if [ -d "/backups/vault" ]; then
        echo "   Backup count: $(ls /backups/vault | wc -l)"
        echo "   Latest backup: $(ls -t /backups/vault | head -1)"
        echo "   Backup size: $(du -sh /backups/vault | cut -f1)"
    fi
    echo ""
    
    echo "Report generated: $(date)"
    echo "=================================================="
    
} > "$REPORT_FILE"

echo "Daily report generated: $REPORT_FILE"

# Optional: Send report via email
# mail -s "Vault Daily Report - $REPORT_DATE" admin@company.com < "$REPORT_FILE"
EOF

chmod +x /vault/scripts/daily-report.sh

# Add to cron for daily reports
echo "0 6 * * * root /vault/scripts/daily-report.sh" >> /etc/crontab
```

## 📋 Monitoring Checklist

### Daily Monitoring Tasks
- [ ] Check service status: `systemctl status vault`
- [ ] Verify Vault is unsealed: `vault status`
- [ ] Review disk usage: `df /var/lib/vault`
- [ ] Check recent audit logs: `tail /var/log/vault/audit.log`
- [ ] Verify backup completion: `ls -la /backups/vault/`

### Weekly Monitoring Tasks
- [ ] Review security alerts: `cat /var/log/vault-security-alerts.log`
- [ ] Check system performance trends
- [ ] Validate certificate expiration dates
- [ ] Review and rotate old backups
- [ ] Test emergency procedures

### Monthly Monitoring Tasks
- [ ] Rotate root token (quarterly)
- [ ] Update Vault version if available
- [ ] Review and update policies
- [ ] Audit user access patterns
- [ ] Performance capacity planning

---

## 📞 Alert Escalation

### Alert Levels
1. **INFO**: Routine status updates
2. **WARN**: Potential issues requiring attention
3. **CRITICAL**: Immediate action required
4. **EMERGENCY**: Service disruption

### Contact Procedures
- **Level 1**: System administrator
- **Level 2**: Security team
- **Level 3**: Management and vendor support

---

**📊 Your operations dashboard is now configured for comprehensive Vault monitoring!**

*Use these tools to maintain visibility into your Vault deployment and ensure optimal performance and security.*

---
*Last Updated: $(date)*
*Operations Dashboard Version: 1.0*