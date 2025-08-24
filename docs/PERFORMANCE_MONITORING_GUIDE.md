# 📈 Vault Performance Monitoring Guide

## 🎯 Performance Monitoring Overview

### Key Performance Indicators (KPIs)

#### System Performance Metrics
| Metric | Target | Warning Threshold | Critical Threshold |
|--------|--------|------------------|-------------------|
| **Response Time** | < 50ms | > 100ms | > 500ms |
| **Throughput** | > 100 req/sec | < 50 req/sec | < 10 req/sec |
| **CPU Usage** | < 70% | > 80% | > 95% |
| **Memory Usage** | < 80% | > 85% | > 95% |
| **Disk Usage** | < 80% | > 85% | > 95% |
| **Network I/O** | < 70% capacity | > 80% capacity | > 95% capacity |

#### Vault-Specific Metrics
| Metric | Target | Warning | Critical |
|--------|--------|---------|----------|
| **Seal Status** | Unsealed | N/A | Sealed |
| **Token Creation Rate** | Stable | High variance | Unable to create |
| **Secret Access Rate** | Stable | High variance | Access failures |
| **Authentication Success** | > 99% | < 95% | < 90% |
| **Audit Log Size** | Managed | Growing fast | Disk full |

## 📊 Performance Monitoring Setup

### System Metrics Collection

#### CPU and Memory Monitoring
```bash
#!/bin/bash
# System performance monitor

cat > /vault/scripts/system-performance-monitor.sh << 'EOF'
#!/bin/bash

METRICS_FILE="/tmp/vault-system-metrics.json"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Collect system metrics
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
MEMORY_TOTAL=$(free -b | grep "Mem:" | awk '{print $2}')
MEMORY_USED=$(free -b | grep "Mem:" | awk '{print $3}')
MEMORY_PERCENT=$(echo "scale=2; $MEMORY_USED * 100 / $MEMORY_TOTAL" | bc)

DISK_USAGE=$(df /var/lib/vault 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")
LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')

# Vault process specific metrics
VAULT_PID=$(pgrep vault)
if [ -n "$VAULT_PID" ]; then
    VAULT_CPU=$(ps -p $VAULT_PID -o %cpu --no-headers | tr -d ' ')
    VAULT_MEMORY=$(ps -p $VAULT_PID -o %mem --no-headers | tr -d ' ')
    VAULT_RSS=$(ps -p $VAULT_PID -o rss --no-headers | tr -d ' ')
else
    VAULT_CPU=0
    VAULT_MEMORY=0
    VAULT_RSS=0
fi

# Network connections
VAULT_CONNECTIONS=$(netstat -an | grep :8200 | grep ESTABLISHED | wc -l)

# Create JSON metrics
cat > "$METRICS_FILE" << EOL
{
  "timestamp": "$TIMESTAMP",
  "system": {
    "cpu_usage": $CPU_USAGE,
    "memory_usage_percent": $MEMORY_PERCENT,
    "memory_total_bytes": $MEMORY_TOTAL,
    "memory_used_bytes": $MEMORY_USED,
    "disk_usage_percent": $DISK_USAGE,
    "load_average": $LOAD_AVG
  },
  "vault_process": {
    "cpu_percent": $VAULT_CPU,
    "memory_percent": $VAULT_MEMORY,
    "memory_rss_kb": $VAULT_RSS,
    "active_connections": $VAULT_CONNECTIONS
  }
}
EOL

echo "System metrics collected: $METRICS_FILE"

# Check thresholds and alert
if (( $(echo "$CPU_USAGE > 80" | bc -l) )); then
    echo "WARNING: High CPU usage: ${CPU_USAGE}%" | tee -a /var/log/vault-alerts.log
fi

if (( $(echo "$MEMORY_PERCENT > 85" | bc -l) )); then
    echo "WARNING: High memory usage: ${MEMORY_PERCENT}%" | tee -a /var/log/vault-alerts.log
fi

if [ "$DISK_USAGE" -gt 85 ]; then
    echo "WARNING: High disk usage: ${DISK_USAGE}%" | tee -a /var/log/vault-alerts.log
fi
EOF

chmod +x /vault/scripts/system-performance-monitor.sh

# Add to cron for regular collection
echo "*/2 * * * * root /vault/scripts/system-performance-monitor.sh" >> /etc/crontab
```

### Vault Application Metrics

#### Vault Performance Collector
```bash
#!/bin/bash
# Vault application performance monitor

cat > /vault/scripts/vault-performance-monitor.sh << 'EOF'
#!/bin/bash

export VAULT_ADDR=${VAULT_ADDR:-https://127.0.0.1:8200}
export VAULT_TOKEN=$(cat /root/.vault/root-token 2>/dev/null)

METRICS_FILE="/tmp/vault-app-metrics.json"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Health check response time
HEALTH_START=$(date +%s%N)
if curl -f -s --max-time 10 "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
    HEALTH_END=$(date +%s%N)
    HEALTH_RESPONSE_TIME=$(( (HEALTH_END - HEALTH_START) / 1000000 )) # milliseconds
    HEALTH_STATUS="healthy"
else
    HEALTH_RESPONSE_TIME=0
    HEALTH_STATUS="unhealthy"
fi

# Vault status
if vault status >/dev/null 2>&1; then
    VAULT_STATUS_JSON=$(vault status -format=json)
    VAULT_SEALED=$(echo "$VAULT_STATUS_JSON" | jq -r '.sealed')
    VAULT_INITIALIZED=$(echo "$VAULT_STATUS_JSON" | jq -r '.initialized')
    VAULT_VERSION=$(echo "$VAULT_STATUS_JSON" | jq -r '.version')
    VAULT_CLUSTER_ID=$(echo "$VAULT_STATUS_JSON" | jq -r '.cluster_id // "unknown"')
else
    VAULT_SEALED="unknown"
    VAULT_INITIALIZED="unknown"
    VAULT_VERSION="unknown"
    VAULT_CLUSTER_ID="unknown"
fi

# Authentication performance test
AUTH_START=$(date +%s%N)
if [ -n "$VAULT_TOKEN" ] && vault auth -method=token token="$VAULT_TOKEN" >/dev/null 2>&1; then
    AUTH_END=$(date +%s%N)
    AUTH_RESPONSE_TIME=$(( (AUTH_END - AUTH_START) / 1000000 ))
    AUTH_STATUS="success"
else
    AUTH_RESPONSE_TIME=0
    AUTH_STATUS="failed"
fi

# Secret read performance test
SECRET_START=$(date +%s%N)
if [ -n "$VAULT_TOKEN" ] && vault kv get secret/test-performance >/dev/null 2>&1; then
    SECRET_END=$(date +%s%N)
    SECRET_RESPONSE_TIME=$(( (SECRET_END - SECRET_START) / 1000000 ))
    SECRET_STATUS="success"
else
    SECRET_RESPONSE_TIME=0
    SECRET_STATUS="failed"
fi

# Recent activity from audit log
if [ -f "/var/log/vault/audit.log" ]; then
    FIVE_MIN_AGO=$(date -d '5 minutes ago' +%s)
    RECENT_REQUESTS=$(tail -1000 /var/log/vault/audit.log | \
        jq -r --arg five_min_ago "$FIVE_MIN_AGO" \
        'select(.time | tonumber > ($five_min_ago | tonumber))' | wc -l)
    
    RECENT_ERRORS=$(tail -1000 /var/log/vault/audit.log | \
        jq -r --arg five_min_ago "$FIVE_MIN_AGO" \
        'select(.time | tonumber > ($five_min_ago | tonumber)) | select(.error != null)' | wc -l)
else
    RECENT_REQUESTS=0
    RECENT_ERRORS=0
fi

# Create JSON metrics
cat > "$METRICS_FILE" << EOL
{
  "timestamp": "$TIMESTAMP",
  "vault_status": {
    "sealed": $VAULT_SEALED,
    "initialized": $VAULT_INITIALIZED,
    "version": "$VAULT_VERSION",
    "cluster_id": "$VAULT_CLUSTER_ID",
    "health_status": "$HEALTH_STATUS"
  },
  "performance": {
    "health_check_ms": $HEALTH_RESPONSE_TIME,
    "auth_response_ms": $AUTH_RESPONSE_TIME,
    "secret_read_ms": $SECRET_RESPONSE_TIME,
    "requests_last_5min": $RECENT_REQUESTS,
    "errors_last_5min": $RECENT_ERRORS
  }
}
EOL

echo "Vault metrics collected: $METRICS_FILE"

# Performance threshold alerts
if [ "$HEALTH_RESPONSE_TIME" -gt 500 ]; then
    echo "WARNING: Slow health check response: ${HEALTH_RESPONSE_TIME}ms" | tee -a /var/log/vault-alerts.log
fi

if [ "$AUTH_RESPONSE_TIME" -gt 1000 ]; then
    echo "WARNING: Slow authentication response: ${AUTH_RESPONSE_TIME}ms" | tee -a /var/log/vault-alerts.log
fi

if [ "$RECENT_ERRORS" -gt 5 ]; then
    echo "WARNING: High error rate: $RECENT_ERRORS errors in last 5 minutes" | tee -a /var/log/vault-alerts.log
fi

if [ "$VAULT_SEALED" = "true" ]; then
    echo "CRITICAL: Vault is sealed!" | tee -a /var/log/vault-alerts.log
fi
EOF

chmod +x /vault/scripts/vault-performance-monitor.sh

# Add to cron for regular collection
echo "*/1 * * * * root /vault/scripts/vault-performance-monitor.sh" >> /etc/crontab
```

## 📊 Real-time Performance Dashboard

### Interactive Performance Monitor
```bash
#!/bin/bash
# Real-time performance dashboard

cat > /vault/scripts/realtime-performance-dashboard.sh << 'EOF'
#!/bin/bash

export VAULT_ADDR=${VAULT_ADDR:-https://127.0.0.1:8200}

while true; do
    clear
    echo "████████████████████████████████████████████████"
    echo "🚀 VAULT PERFORMANCE DASHBOARD"
    echo "████████████████████████████████████████████████"
    echo "Updated: $(date)"
    echo ""
    
    # System Performance
    echo "💻 SYSTEM PERFORMANCE"
    echo "===================="
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
    MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    DISK_USAGE=$(df /var/lib/vault 2>/dev/null | tail -1 | awk '{print $5}' || echo "N/A")
    LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')
    
    # Color coding for CPU
    if (( $(echo "$CPU_USAGE > 80" | bc -l) )); then
        CPU_COLOR="\033[0;31m" # Red
    elif (( $(echo "$CPU_USAGE > 60" | bc -l) )); then
        CPU_COLOR="\033[0;33m" # Yellow
    else
        CPU_COLOR="\033[0;32m" # Green
    fi
    
    echo -e "CPU Usage:    ${CPU_COLOR}${CPU_USAGE}%\033[0m"
    echo -e "Memory Usage: ${MEMORY_USAGE}%"
    echo -e "Disk Usage:   ${DISK_USAGE}"
    echo -e "Load Average: ${LOAD_AVG}"
    
    # Vault Status
    echo ""
    echo "🏛️ VAULT STATUS"
    echo "==============="
    
    # Health check with timing
    HEALTH_START=$(date +%s%N)
    if curl -f -s --max-time 5 "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
        HEALTH_END=$(date +%s%N)
        HEALTH_TIME=$(( (HEALTH_END - HEALTH_START) / 1000000 ))
        echo -e "Health Check: \033[0;32m✅ HEALTHY\033[0m (${HEALTH_TIME}ms)"
        
        # Get Vault status details
        if VAULT_STATUS=$(vault status -format=json 2>/dev/null); then
            SEALED=$(echo "$VAULT_STATUS" | jq -r '.sealed')
            if [ "$SEALED" = "false" ]; then
                echo -e "Vault Status: \033[0;32m🔓 UNSEALED\033[0m"
            else
                echo -e "Vault Status: \033[0;31m🔒 SEALED\033[0m"
            fi
            
            VERSION=$(echo "$VAULT_STATUS" | jq -r '.version')
            echo "Version:      $VERSION"
        fi
    else
        echo -e "Health Check: \033[0;31m❌ UNHEALTHY\033[0m"
        echo -e "Vault Status: \033[0;31m🚫 UNREACHABLE\033[0m"
    fi
    
    # Performance Metrics
    echo ""
    echo "⚡ PERFORMANCE METRICS (Last 5 minutes)"
    echo "======================================"
    
    if [ -f "/var/log/vault/audit.log" ]; then
        FIVE_MIN_AGO=$(date -d '5 minutes ago' +%s)
        
        # Request rate
        REQUESTS=$(tail -1000 /var/log/vault/audit.log | \
            jq -r --arg five_min_ago "$FIVE_MIN_AGO" \
            'select(.time | tonumber > ($five_min_ago | tonumber))' | wc -l)
        REQUESTS_PER_MIN=$(echo "scale=1; $REQUESTS / 5" | bc)
        
        # Error rate
        ERRORS=$(tail -1000 /var/log/vault/audit.log | \
            jq -r --arg five_min_ago "$FIVE_MIN_AGO" \
            'select(.time | tonumber > ($five_min_ago | tonumber)) | select(.error != null)' | wc -l)
        
        ERROR_RATE=0
        if [ "$REQUESTS" -gt 0 ]; then
            ERROR_RATE=$(echo "scale=2; $ERRORS * 100 / $REQUESTS" | bc)
        fi
        
        echo "Requests:     $REQUESTS total (${REQUESTS_PER_MIN}/min)"
        echo "Errors:       $ERRORS ($ERROR_RATE%)"
        
        # Top request paths
        echo ""
        echo "🔥 TOP REQUEST PATHS:"
        tail -500 /var/log/vault/audit.log | \
            jq -r --arg five_min_ago "$FIVE_MIN_AGO" \
            'select(.time | tonumber > ($five_min_ago | tonumber)) | .request.path // "unknown"' | \
            sort | uniq -c | sort -nr | head -5 | \
            awk '{printf "   %-3s %s\\n", $1, $2}'
    else
        echo "No audit log data available"
    fi
    
    # Network Activity
    echo ""
    echo "🌐 NETWORK ACTIVITY"
    echo "=================="
    CONNECTIONS=$(netstat -an | grep :8200 | grep ESTABLISHED | wc -l)
    LISTENING=$(netstat -tlnp | grep :8200 | wc -l)
    
    echo "Active Connections: $CONNECTIONS"
    echo "Listening Sockets:  $LISTENING"
    
    # Memory Details
    echo ""
    echo "🧠 MEMORY DETAILS"
    echo "================="
    if [ -n "$(pgrep vault)" ]; then
        VAULT_PID=$(pgrep vault)
        VAULT_RSS=$(ps -p $VAULT_PID -o rss --no-headers | tr -d ' ')
        VAULT_VSZ=$(ps -p $VAULT_PID -o vsz --no-headers | tr -d ' ')
        
        echo "Vault RSS:    ${VAULT_RSS} KB"
        echo "Vault VSZ:    ${VAULT_VSZ} KB"
    else
        echo "Vault process not found"
    fi
    
    # Storage Info
    echo ""
    echo "💾 STORAGE INFO"
    echo "==============="
    if [ -d "/var/lib/vault" ]; then
        VAULT_SIZE=$(du -sh /var/lib/vault 2>/dev/null | cut -f1 || echo "unknown")
        echo "Vault Data:   $VAULT_SIZE"
    fi
    
    if [ -f "/var/log/vault/audit.log" ]; then
        AUDIT_SIZE=$(du -sh /var/log/vault/audit.log 2>/dev/null | cut -f1 || echo "unknown")
        echo "Audit Log:    $AUDIT_SIZE"
    fi
    
    echo ""
    echo "████████████████████████████████████████████████"
    echo "Press Ctrl+C to exit | Refreshing in 5 seconds..."
    sleep 5
done
EOF

chmod +x /vault/scripts/realtime-performance-dashboard.sh
```

## 📈 Performance Analytics

### Historical Performance Analysis
```bash
#!/bin/bash
# Historical performance analysis

cat > /vault/scripts/performance-analysis.sh << 'EOF'
#!/bin/bash

echo "📈 VAULT PERFORMANCE ANALYSIS"
echo "============================"

ANALYSIS_DAYS=${1:-7}
echo "Analyzing performance for the last $ANALYSIS_DAYS days"
echo ""

# CPU Usage Trend Analysis
echo "💻 CPU USAGE TREND"
echo "=================="

# This would typically use stored metrics from a time-series database
# For demo purposes, we'll analyze recent system data

if command -v sar >/dev/null 2>&1; then
    echo "Average CPU usage (last 24 hours):"
    sar -u 1 1 | tail -1 | awk '{print "   " $3"% user, " $5"% system, " $8"% idle"}'
else
    echo "SAR not available for historical CPU analysis"
fi

echo ""

# Memory Usage Analysis
echo "🧠 MEMORY USAGE ANALYSIS"
echo "======================="

CURRENT_MEMORY=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
echo "Current memory usage: ${CURRENT_MEMORY}%"

# Vault process memory growth (if available)
if [ -n "$(pgrep vault)" ]; then
    VAULT_PID=$(pgrep vault)
    VAULT_MEMORY=$(ps -p $VAULT_PID -o %mem --no-headers | tr -d ' ')
    echo "Vault process memory: ${VAULT_MEMORY}%"
fi

echo ""

# Request Pattern Analysis
echo "📊 REQUEST PATTERN ANALYSIS"
echo "=========================="

if [ -f "/var/log/vault/audit.log" ]; then
    # Analyze request patterns by hour
    echo "Requests by hour (last 24 hours):"
    
    for hour in {0..23}; do
        HOUR_FORMATTED=$(printf "%02d" $hour)
        HOUR_REQUESTS=$(tail -10000 /var/log/vault/audit.log | \
            grep "$(date +%Y-%m-%d)" | \
            grep "T${HOUR_FORMATTED}:" | wc -l)
        
        # Create simple bar chart
        BAR=""
        if [ "$HOUR_REQUESTS" -gt 0 ]; then
            BAR_LENGTH=$(($HOUR_REQUESTS / 5)) # Scale factor
            [ "$BAR_LENGTH" -gt 50 ] && BAR_LENGTH=50 # Max bar length
            BAR=$(printf "%-${BAR_LENGTH}s" | tr ' ' '█')
        fi
        
        printf "   %02d:00 │%-50s│ %d\n" "$hour" "$BAR" "$HOUR_REQUESTS"
    done
    
    echo ""
    
    # Error rate analysis
    echo "ERROR RATE ANALYSIS"
    echo "=================="
    
    TOTAL_REQUESTS=$(tail -10000 /var/log/vault/audit.log | \
        grep "$(date +%Y-%m-%d)" | wc -l)
    
    ERROR_REQUESTS=$(tail -10000 /var/log/vault/audit.log | \
        grep "$(date +%Y-%m-%d)" | \
        jq -r 'select(.error != null)' | wc -l)
    
    if [ "$TOTAL_REQUESTS" -gt 0 ]; then
        ERROR_RATE=$(echo "scale=2; $ERROR_REQUESTS * 100 / $TOTAL_REQUESTS" | bc)
        echo "Total requests today: $TOTAL_REQUESTS"
        echo "Error requests today: $ERROR_REQUESTS"
        echo "Error rate: ${ERROR_RATE}%"
        
        if (( $(echo "$ERROR_RATE > 1" | bc -l) )); then
            echo "⚠️ High error rate detected!"
        else
            echo "✅ Error rate within normal range"
        fi
    else
        echo "No requests found for analysis"
    fi
    
    echo ""
    
    # Authentication method usage
    echo "AUTHENTICATION METHOD USAGE"
    echo "=========================="
    tail -5000 /var/log/vault/audit.log | \
        jq -r 'select(.request.path | test("auth/")) | .request.path' | \
        cut -d'/' -f2 | sort | uniq -c | sort -nr | \
        awk '{printf "   %-15s %d requests\n", $2, $1}' | head -10
    
else
    echo "Audit log not available for request analysis"
fi

echo ""

# Performance Recommendations
echo "🎯 PERFORMANCE RECOMMENDATIONS"
echo "============================="

# Check current resource usage and make recommendations
CURRENT_CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
CURRENT_MEMORY=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
CURRENT_DISK=$(df /var/lib/vault 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")

if (( $(echo "$CURRENT_CPU > 70" | bc -l) )); then
    echo "🔧 CPU usage is high (${CURRENT_CPU}%) - consider:"
    echo "   - Adding more CPU cores"
    echo "   - Optimizing application logic"
    echo "   - Load balancing across multiple instances"
fi

if [ "$CURRENT_MEMORY" -gt 80 ]; then
    echo "🔧 Memory usage is high (${CURRENT_MEMORY}%) - consider:"
    echo "   - Adding more RAM"
    echo "   - Tuning Vault cache settings"
    echo "   - Reviewing memory leaks"
fi

if [ "$CURRENT_DISK" -gt 75 ]; then
    echo "🔧 Disk usage is high (${CURRENT_DISK}%) - consider:"
    echo "   - Adding more storage"
    echo "   - Implementing log rotation"
    echo "   - Archiving old audit logs"
fi

# Network recommendations
CONNECTIONS=$(netstat -an | grep :8200 | grep ESTABLISHED | wc -l)
if [ "$CONNECTIONS" -gt 100 ]; then
    echo "🔧 High connection count ($CONNECTIONS) - consider:"
    echo "   - Connection pooling"
    echo "   - Load balancing"
    echo "   - Connection limits"
fi

echo ""
echo "Analysis completed: $(date)"
EOF

chmod +x /vault/scripts/performance-analysis.sh
```

## 🔔 Performance Alerting

### Automated Performance Alerts
```bash
#!/bin/bash
# Performance alerting system

cat > /vault/scripts/performance-alerting.sh << 'EOF'
#!/bin/bash

ALERT_LOG="/var/log/vault-performance-alerts.log"
CONFIG_FILE="/etc/vault-performance-thresholds.conf"

# Create default thresholds config if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" << 'EOC'
# Vault Performance Alert Thresholds
CPU_WARNING_THRESHOLD=70
CPU_CRITICAL_THRESHOLD=90
MEMORY_WARNING_THRESHOLD=80
MEMORY_CRITICAL_THRESHOLD=95
DISK_WARNING_THRESHOLD=80
DISK_CRITICAL_THRESHOLD=90
RESPONSE_TIME_WARNING=500
RESPONSE_TIME_CRITICAL=2000
ERROR_RATE_WARNING=2
ERROR_RATE_CRITICAL=5
EOC
fi

# Source thresholds
source "$CONFIG_FILE"

send_alert() {
    local level="$1"
    local message="$2"
    local timestamp=$(date)
    
    echo "[$timestamp] $level: $message" | tee -a "$ALERT_LOG"
    
    # Integration points for alerting systems
    case "$level" in
        "CRITICAL")
            # Send to critical alerting channel
            echo "$message" | logger -t vault-critical -p local0.crit
            # Add webhook/email/SMS integration here
            ;;
        "WARNING")
            # Send to warning alerting channel
            echo "$message" | logger -t vault-warning -p local0.warning
            # Add notification integration here
            ;;
    esac
}

check_system_performance() {
    # CPU Check
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}' | awk '{print int($1)}')
    
    if [ "$CPU_USAGE" -ge "$CPU_CRITICAL_THRESHOLD" ]; then
        send_alert "CRITICAL" "CPU usage critical: ${CPU_USAGE}% (threshold: ${CPU_CRITICAL_THRESHOLD}%)"
    elif [ "$CPU_USAGE" -ge "$CPU_WARNING_THRESHOLD" ]; then
        send_alert "WARNING" "CPU usage high: ${CPU_USAGE}% (threshold: ${CPU_WARNING_THRESHOLD}%)"
    fi
    
    # Memory Check
    MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    
    if [ "$MEMORY_USAGE" -ge "$MEMORY_CRITICAL_THRESHOLD" ]; then
        send_alert "CRITICAL" "Memory usage critical: ${MEMORY_USAGE}% (threshold: ${MEMORY_CRITICAL_THRESHOLD}%)"
    elif [ "$MEMORY_USAGE" -ge "$MEMORY_WARNING_THRESHOLD" ]; then
        send_alert "WARNING" "Memory usage high: ${MEMORY_USAGE}% (threshold: ${MEMORY_WARNING_THRESHOLD}%)"
    fi
    
    # Disk Check
    DISK_USAGE=$(df /var/lib/vault 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")
    
    if [ "$DISK_USAGE" -ge "$DISK_CRITICAL_THRESHOLD" ]; then
        send_alert "CRITICAL" "Disk usage critical: ${DISK_USAGE}% (threshold: ${DISK_CRITICAL_THRESHOLD}%)"
    elif [ "$DISK_USAGE" -ge "$DISK_WARNING_THRESHOLD" ]; then
        send_alert "WARNING" "Disk usage high: ${DISK_USAGE}% (threshold: ${DISK_WARNING_THRESHOLD}%)"
    fi
}

check_vault_performance() {
    export VAULT_ADDR=${VAULT_ADDR:-https://127.0.0.1:8200}
    
    # Response Time Check
    HEALTH_START=$(date +%s%N)
    if curl -f -s --max-time 10 "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
        HEALTH_END=$(date +%s%N)
        RESPONSE_TIME=$(( (HEALTH_END - HEALTH_START) / 1000000 ))
        
        if [ "$RESPONSE_TIME" -ge "$RESPONSE_TIME_CRITICAL" ]; then
            send_alert "CRITICAL" "Vault response time critical: ${RESPONSE_TIME}ms (threshold: ${RESPONSE_TIME_CRITICAL}ms)"
        elif [ "$RESPONSE_TIME" -ge "$RESPONSE_TIME_WARNING" ]; then
            send_alert "WARNING" "Vault response time high: ${RESPONSE_TIME}ms (threshold: ${RESPONSE_TIME_WARNING}ms)"
        fi
    else
        send_alert "CRITICAL" "Vault health check failed - service may be down"
    fi
    
    # Vault Seal Status
    if vault status >/dev/null 2>&1; then
        SEALED=$(vault status -format=json | jq -r '.sealed')
        if [ "$SEALED" = "true" ]; then
            send_alert "CRITICAL" "Vault is sealed - immediate attention required"
        fi
    else
        send_alert "CRITICAL" "Cannot check Vault status - service may be unreachable"
    fi
    
    # Error Rate Check
    if [ -f "/var/log/vault/audit.log" ]; then
        FIVE_MIN_AGO=$(date -d '5 minutes ago' +%s)
        
        RECENT_REQUESTS=$(tail -1000 /var/log/vault/audit.log | \
            jq -r --arg five_min_ago "$FIVE_MIN_AGO" \
            'select(.time | tonumber > ($five_min_ago | tonumber))' | wc -l)
        
        RECENT_ERRORS=$(tail -1000 /var/log/vault/audit.log | \
            jq -r --arg five_min_ago "$FIVE_MIN_AGO" \
            'select(.time | tonumber > ($five_min_ago | tonumber)) | select(.error != null)' | wc -l)
        
        if [ "$RECENT_REQUESTS" -gt 10 ]; then # Only check if there's meaningful traffic
            ERROR_RATE=$(echo "scale=2; $RECENT_ERRORS * 100 / $RECENT_REQUESTS" | bc)
            ERROR_RATE_INT=$(echo "$ERROR_RATE" | cut -d. -f1)
            
            if [ "$ERROR_RATE_INT" -ge "$ERROR_RATE_CRITICAL" ]; then
                send_alert "CRITICAL" "Error rate critical: ${ERROR_RATE}% (${RECENT_ERRORS}/${RECENT_REQUESTS}) in last 5 minutes"
            elif [ "$ERROR_RATE_INT" -ge "$ERROR_RATE_WARNING" ]; then
                send_alert "WARNING" "Error rate high: ${ERROR_RATE}% (${RECENT_ERRORS}/${RECENT_REQUESTS}) in last 5 minutes"
            fi
        fi
    fi
}

# Run all checks
echo "Running performance checks at $(date)"
check_system_performance
check_vault_performance
echo "Performance checks completed"
EOF

chmod +x /vault/scripts/performance-alerting.sh

# Add to cron for regular monitoring
echo "*/5 * * * * root /vault/scripts/performance-alerting.sh" >> /etc/crontab
```

## 📊 Performance Optimization

### Performance Tuning Guide
```bash
#!/bin/bash
# Performance optimization recommendations

cat > /vault/scripts/performance-optimization.sh << 'EOF'
#!/bin/bash

echo "🚀 VAULT PERFORMANCE OPTIMIZATION"
echo "================================="

export VAULT_ADDR=${VAULT_ADDR:-https://127.0.0.1:8200}
export VAULT_TOKEN=$(cat /root/.vault/root-token 2>/dev/null)

# Analyze current performance
echo "📊 CURRENT PERFORMANCE ANALYSIS"
echo "==============================="

# System resources
CPU_CORES=$(nproc)
TOTAL_MEMORY=$(free -h | grep Mem | awk '{print $2}')
VAULT_MEMORY=$(ps -p $(pgrep vault) -o rss --no-headers 2>/dev/null | awk '{print int($1/1024)}' || echo "0")

echo "CPU Cores:        $CPU_CORES"
echo "Total Memory:     $TOTAL_MEMORY"
echo "Vault Memory:     ${VAULT_MEMORY}MB"

# Current configuration analysis
echo ""
echo "🔧 CONFIGURATION ANALYSIS"
echo "========================="

if [ -f "/etc/vault.d/vault.hcl" ]; then
    # Check cache size
    if grep -q "cache_size" /etc/vault.d/vault.hcl; then
        CACHE_SIZE=$(grep "cache_size" /etc/vault.d/vault.hcl | awk '{print $3}')
        echo "Current cache size: $CACHE_SIZE"
    else
        echo "Cache size: Not configured (using default)"
    fi
    
    # Check disable_mlock
    if grep -q "disable_mlock.*false" /etc/vault.d/vault.hcl; then
        echo "Memory locking: Enabled (good for security)"
    elif grep -q "disable_mlock.*true" /etc/vault.d/vault.hcl; then
        echo "Memory locking: Disabled (consider enabling for production)"
    fi
    
    # Check log level
    if grep -q "log_level" /etc/vault.d/vault.hcl; then
        LOG_LEVEL=$(grep "log_level" /etc/vault.d/vault.hcl | awk '{print $3}' | tr -d '"')
        echo "Log level: $LOG_LEVEL"
    else
        echo "Log level: Default (info)"
    fi
fi

# Performance recommendations
echo ""
echo "💡 OPTIMIZATION RECOMMENDATIONS"
echo "==============================="

# Memory recommendations
AVAILABLE_MEMORY_GB=$(free -g | grep Mem | awk '{print $2}')
RECOMMENDED_CACHE_SIZE=$((AVAILABLE_MEMORY_GB * 1024 * 128)) # ~12.5% of available memory

if [ -f "/etc/vault.d/vault.hcl" ] && grep -q "cache_size" /etc/vault.d/vault.hcl; then
    CURRENT_CACHE=$(grep "cache_size" /etc/vault.d/vault.hcl | awk '{print $3}')
    if [ "$CURRENT_CACHE" -lt "$RECOMMENDED_CACHE_SIZE" ]; then
        echo "🔧 Consider increasing cache_size to $RECOMMENDED_CACHE_SIZE"
        echo "   Current: $CURRENT_CACHE, Recommended: $RECOMMENDED_CACHE_SIZE"
    fi
else
    echo "🔧 Consider adding cache_size = $RECOMMENDED_CACHE_SIZE to vault.hcl"
fi

# Performance tuning based on usage patterns
if [ -f "/var/log/vault/audit.log" ]; then
    RECENT_REQUESTS=$(tail -1000 /var/log/vault/audit.log | \
        jq -r 'select(.time | tonumber > (now - 3600))' | wc -l)
    
    if [ "$RECENT_REQUESTS" -gt 1000 ]; then
        echo "🔧 High traffic detected ($RECENT_REQUESTS req/hour) - consider:"
        echo "   - Horizontal scaling (multiple Vault instances)"
        echo "   - Load balancing"
        echo "   - Connection pooling in applications"
        echo "   - Caching frequently accessed secrets"
    fi
fi

# System-level optimizations
echo ""
echo "🖥️ SYSTEM-LEVEL OPTIMIZATIONS"
echo "============================="

# File descriptor limits
CURRENT_ULIMIT=$(ulimit -n)
if [ "$CURRENT_ULIMIT" -lt 65536 ]; then
    echo "🔧 Increase file descriptor limit:"
    echo "   Current: $CURRENT_ULIMIT, Recommended: 65536"
    echo "   Add to /etc/security/limits.conf:"
    echo "   vault soft nofile 65536"
    echo "   vault hard nofile 65536"
fi

# Check if running on SSD
if lsblk -d -o name,rota | grep -q "0$"; then
    echo "✅ SSD storage detected - good for performance"
else
    echo "🔧 Consider using SSD storage for better I/O performance"
fi

# Network optimizations
echo ""
echo "🌐 NETWORK OPTIMIZATIONS"
echo "======================="

# Check TCP settings
TCP_WINDOW=$(sysctl -n net.core.rmem_max)
if [ "$TCP_WINDOW" -lt 134217728 ]; then # 128MB
    echo "🔧 Consider tuning TCP buffer sizes:"
    echo "   net.core.rmem_max = 134217728"
    echo "   net.core.wmem_max = 134217728"
fi

# Application-level optimizations
echo ""
echo "📱 APPLICATION-LEVEL OPTIMIZATIONS"
echo "=================================="

echo "🔧 Vault configuration optimizations:"
cat << 'EOCONFIG'

# Add to vault.hcl for better performance:

# Increase cache size (adjust based on available memory)
cache_size = 131072

# Optimize lease TTLs
default_lease_ttl = "168h"    # 1 week
max_lease_ttl = "720h"        # 30 days

# Request timeout
default_max_request_duration = "90s"

# Disable performance standby if not needed
disable_performance_standby = true

# Log optimization for high traffic
log_level = "warn"  # Reduce log verbosity in production

# Connection limits
listener "tcp" {
  # ... existing config ...
  max_request_size = 33554432  # 32MB
  max_request_duration = "90s"
}

# Telemetry for monitoring
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname = false
}
EOCONFIG

# Backup and maintenance recommendations
echo ""
echo "💾 MAINTENANCE RECOMMENDATIONS"
echo "============================="

echo "🔧 Regular maintenance tasks:"
echo "   - Monitor and rotate audit logs"
echo "   - Regular backup verification"
echo "   - Token cleanup (revoke unused tokens)"
echo "   - Certificate renewal planning"
echo "   - Performance baseline reviews"

# Auto-optimization script
echo ""
echo "🤖 AUTO-OPTIMIZATION AVAILABLE"
echo "============================"
echo "Run the following to apply safe optimizations:"
echo "   /vault/scripts/apply-performance-optimizations.sh"

echo ""
echo "Performance analysis completed: $(date)"
EOF

chmod +x /vault/scripts/performance-optimization.sh
```

### Automated Optimization Application
```bash
#!/bin/bash
# Apply safe performance optimizations

cat > /vault/scripts/apply-performance-optimizations.sh << 'EOF'
#!/bin/bash

echo "🚀 APPLYING VAULT PERFORMANCE OPTIMIZATIONS"
echo "==========================================="

# Safety check
read -p "This will modify system and Vault configuration. Continue? (y/N): " -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Optimization cancelled"
    exit 0
fi

# Create backup
echo "Creating configuration backup..."
BACKUP_DIR="/backups/vault-optimization-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/vault.d/vault.hcl "$BACKUP_DIR/" 2>/dev/null || true
cp /etc/security/limits.conf "$BACKUP_DIR/" 2>/dev/null || true

# Apply system-level optimizations
echo ""
echo "Applying system optimizations..."

# File descriptor limits
if ! grep -q "vault.*nofile" /etc/security/limits.conf; then
    echo "vault soft nofile 65536" >> /etc/security/limits.conf
    echo "vault hard nofile 65536" >> /etc/security/limits.conf
    echo "✅ File descriptor limits increased"
fi

# Apply Vault configuration optimizations
echo ""
echo "Applying Vault configuration optimizations..."

VAULT_CONFIG="/etc/vault.d/vault.hcl"
if [ -f "$VAULT_CONFIG" ]; then
    # Add cache_size if not present
    if ! grep -q "cache_size" "$VAULT_CONFIG"; then
        MEMORY_GB=$(free -g | grep Mem | awk '{print $2}')
        CACHE_SIZE=$((MEMORY_GB * 1024 * 128))
        
        # Add cache_size to configuration
        sed -i "/^cluster_name/a cache_size = $CACHE_SIZE" "$VAULT_CONFIG"
        echo "✅ Cache size configured: $CACHE_SIZE"
    fi
    
    # Add request timeout if not present
    if ! grep -q "default_max_request_duration" "$VAULT_CONFIG"; then
        sed -i "/^cluster_name/a default_max_request_duration = \"90s\"" "$VAULT_CONFIG"
        echo "✅ Request timeout configured"
    fi
    
    # Restart Vault to apply changes
    echo ""
    echo "Restarting Vault to apply configuration changes..."
    systemctl restart vault
    sleep 10
    
    # Verify Vault is running
    if systemctl is-active --quiet vault; then
        echo "✅ Vault restarted successfully"
        
        # Check if unsealed
        export VAULT_ADDR=${VAULT_ADDR:-https://127.0.0.1:8200}
        if vault status >/dev/null 2>&1; then
            SEALED=$(vault status -format=json | jq -r '.sealed')
            if [ "$SEALED" = "true" ]; then
                echo "ℹ️ Vault is sealed - you may need to unseal it"
            else
                echo "✅ Vault is unsealed and operational"
            fi
        fi
    else
        echo "❌ Vault restart failed - restoring backup"
        cp "$BACKUP_DIR/vault.hcl" "$VAULT_CONFIG"
        systemctl restart vault
        exit 1
    fi
fi

echo ""
echo "✅ OPTIMIZATION COMPLETED"
echo "======================="
echo "Backup saved to: $BACKUP_DIR"
echo "Monitor performance for improvements"
echo ""
echo "Next steps:"
echo "- Monitor /var/log/vault/vault.log for any issues"
echo "- Run performance dashboard to see improvements"
echo "- Consider additional optimizations based on usage patterns"

EOF

chmod +x /vault/scripts/apply-performance-optimizations.sh
```

---

## 📋 Performance Monitoring Checklist

### Daily Performance Tasks
- [ ] Check real-time dashboard for anomalies
- [ ] Review overnight performance alerts
- [ ] Verify system resource utilization is within thresholds
- [ ] Monitor Vault response times
- [ ] Check error rates in audit logs

### Weekly Performance Tasks
- [ ] Run comprehensive performance analysis
- [ ] Review performance trends and capacity planning
- [ ] Check for performance optimization opportunities
- [ ] Validate alerting thresholds are appropriate
- [ ] Update performance baselines if needed

### Monthly Performance Tasks
- [ ] Conduct detailed performance review
- [ ] Analyze historical trends and patterns
- [ ] Review and update performance thresholds
- [ ] Plan capacity upgrades if needed
- [ ] Performance benchmark comparison

---

## 📞 Performance Support

### Performance Escalation
1. **Level 1**: Investigate using monitoring tools
2. **Level 2**: Apply standard optimizations
3. **Level 3**: Engage performance specialists
4. **Level 4**: Vendor support and consulting

### Key Performance Contacts
- **System Administrator**: Primary performance monitoring
- **Vault Administrator**: Application-specific performance
- **Infrastructure Team**: Hardware and network optimization
- **Development Team**: Application integration optimization

---

**📈 Your performance monitoring system is now fully configured for comprehensive Vault performance management!**

*Use these tools to maintain optimal Vault performance and proactively address any performance issues.*

---
*Last Updated: $(date)*
*Performance Monitoring Guide Version: 1.0*