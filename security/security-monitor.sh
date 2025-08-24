#!/bin/bash

# Vault Security Monitoring and Compliance System
# Continuous security monitoring, threat detection, and compliance validation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_DIR="/var/log/vault/monitoring"
METRICS_DIR="/var/log/vault/metrics"
ALERTS_DIR="/var/log/vault/alerts"
VAULT_ADDR="${VAULT_ADDR:-https://127.0.0.1:8200}"
ALERT_EMAIL="${ALERT_EMAIL:-admin@cloudya.net}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
MONITORING_INTERVAL="${MONITORING_INTERVAL:-60}"
THREAT_THRESHOLD="${THREAT_THRESHOLD:-5}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Initialize monitoring system
init_monitoring() {
    log_step "Initializing security monitoring system..."
    
    # Create directories
    mkdir -p "$MONITOR_DIR" "$METRICS_DIR" "$ALERTS_DIR"
    
    # Set permissions
    chmod 750 "$MONITOR_DIR" "$METRICS_DIR" "$ALERTS_DIR"
    
    if id vault &>/dev/null; then
        chown -R vault:vault "$MONITOR_DIR" "$METRICS_DIR" "$ALERTS_DIR"
    fi
    
    # Install monitoring dependencies
    if ! command -v jq >/dev/null; then
        log_step "Installing jq..."
        if [[ -f /etc/redhat-release ]]; then
            dnf install -y jq
        elif [[ -f /etc/debian_version ]]; then
            apt-get update && apt-get install -y jq
        fi
    fi
    
    # Create monitoring configuration
    cat > "$MONITOR_DIR/config.json" << EOF
{
  "monitoring": {
    "enabled": true,
    "interval": $MONITORING_INTERVAL,
    "threat_threshold": $THREAT_THRESHOLD,
    "alert_channels": {
      "email": "$ALERT_EMAIL",
      "slack": "$SLACK_WEBHOOK"
    }
  },
  "checks": {
    "vault_health": true,
    "authentication_anomalies": true,
    "token_abuse": true,
    "policy_changes": true,
    "seal_status": true,
    "performance_metrics": true,
    "certificate_expiry": true,
    "backup_integrity": true
  },
  "thresholds": {
    "failed_auth_per_minute": 10,
    "token_creation_per_minute": 20,
    "high_privilege_operations_per_hour": 5,
    "response_time_ms": 1000,
    "cpu_usage_percent": 80,
    "memory_usage_percent": 80,
    "disk_usage_percent": 85
  }
}
EOF
    
    log_info "✅ Security monitoring system initialized"
}

# Send alerts
send_alert() {
    local severity="$1"
    local title="$2"
    local message="$3"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Log alert
    local alert_entry=$(cat << EOF
{
  "timestamp": "$timestamp",
  "severity": "$severity",
  "title": "$title", 
  "message": "$message",
  "hostname": "$(hostname)",
  "vault_addr": "$VAULT_ADDR"
}
EOF
    )
    
    echo "$alert_entry" >> "$ALERTS_DIR/security-alerts.log"
    
    # Send email alert
    if command -v mail >/dev/null && [[ -n "$ALERT_EMAIL" ]]; then
        local subject="🛡️ Vault Security Alert [$severity] - $title"
        echo "Vault Security Alert

Severity: $severity
Title: $title
Time: $timestamp
Host: $(hostname)

Details:
$message

This is an automated security alert from Vault monitoring system." | \
            mail -s "$subject" "$ALERT_EMAIL"
    fi
    
    # Send Slack alert
    if [[ -n "$SLACK_WEBHOOK" ]]; then
        local slack_color
        case "$severity" in
            "CRITICAL") slack_color="danger" ;;
            "HIGH") slack_color="warning" ;;
            "MEDIUM") slack_color="warning" ;;
            "LOW") slack_color="good" ;;
            *) slack_color="#36a64f" ;;
        esac
        
        curl -X POST -H 'Content-type: application/json' \
            --data "{
                \"attachments\": [{
                    \"color\": \"$slack_color\",
                    \"title\": \"🛡️ Vault Security Alert - $severity\",
                    \"text\": \"$title\",
                    \"fields\": [
                        {\"title\": \"Host\", \"value\": \"$(hostname)\", \"short\": true},
                        {\"title\": \"Time\", \"value\": \"$timestamp\", \"short\": true},
                        {\"title\": \"Details\", \"value\": \"$message\", \"short\": false}
                    ]
                }]
            }" "$SLACK_WEBHOOK" >/dev/null 2>&1 || true
    fi
    
    # System log
    logger -t "vault-security" -p auth.warning "[$severity] $title: $message"
}

# Check Vault health
check_vault_health() {
    local health_data
    local health_issues=()
    
    # Get health status
    if ! health_data=$(curl -s -k "$VAULT_ADDR/v1/sys/health" 2>/dev/null); then
        health_issues+=("Cannot connect to Vault API")
        send_alert "CRITICAL" "Vault API Unavailable" "Cannot connect to Vault at $VAULT_ADDR"
        return 1
    fi
    
    # Parse health data
    local initialized=$(echo "$health_data" | jq -r '.initialized')
    local sealed=$(echo "$health_data" | jq -r '.sealed')
    local standby=$(echo "$health_data" | jq -r '.standby')
    local performance_standby=$(echo "$health_data" | jq -r '.performance_standby')
    local replication_performance_mode=$(echo "$health_data" | jq -r '.replication_performance_mode')
    local replication_dr_mode=$(echo "$health_data" | jq -r '.replication_dr_mode')
    local server_time_utc=$(echo "$health_data" | jq -r '.server_time_utc')
    local version=$(echo "$health_data" | jq -r '.version')
    local cluster_name=$(echo "$health_data" | jq -r '.cluster_name')
    local cluster_id=$(echo "$health_data" | jq -r '.cluster_id')
    
    # Check initialization
    if [[ "$initialized" != "true" ]]; then
        health_issues+=("Vault is not initialized")
        send_alert "CRITICAL" "Vault Not Initialized" "Vault instance is not initialized"
    fi
    
    # Check seal status
    if [[ "$sealed" == "true" ]]; then
        health_issues+=("Vault is sealed")
        send_alert "CRITICAL" "Vault Sealed" "Vault instance is sealed and unavailable"
    fi
    
    # Log health metrics
    local health_metrics=$(cat << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "initialized": $initialized,
  "sealed": $sealed,
  "standby": $standby,
  "performance_standby": $performance_standby,
  "replication_performance_mode": "$replication_performance_mode",
  "replication_dr_mode": "$replication_dr_mode",
  "server_time_utc": $server_time_utc,
  "version": "$version",
  "cluster_name": "$cluster_name",
  "cluster_id": "$cluster_id",
  "issues": [$(printf '"%s",' "${health_issues[@]}" | sed 's/,$//')]
}
EOF
    )
    
    echo "$health_metrics" >> "$METRICS_DIR/health-metrics.log"
    
    if [[ ${#health_issues[@]} -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Monitor authentication patterns
monitor_authentication() {
    local audit_log="/var/log/vault/audit/vault-audit.log"
    local now=$(date +%s)
    local minute_ago=$((now - 60))
    local auth_failures=0
    local auth_successes=0
    local unique_ips=()
    local suspicious_patterns=()
    
    if [[ ! -f "$audit_log" ]]; then
        return 0
    fi
    
    # Analyze recent authentication events
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        # Parse JSON audit entry
        local event_time event_type request_path error client_ip
        if event_time=$(echo "$line" | jq -r '.time' 2>/dev/null) &&
           event_type=$(echo "$line" | jq -r '.type' 2>/dev/null) &&
           request_path=$(echo "$line" | jq -r '.request.path // ""' 2>/dev/null) &&
           error=$(echo "$line" | jq -r '.error // ""' 2>/dev/null) &&
           client_ip=$(echo "$line" | jq -r '.request.client_ip // ""' 2>/dev/null); then
            
            # Convert time to epoch
            local event_epoch
            if event_epoch=$(date -d "$event_time" +%s 2>/dev/null); then
                # Only process recent events
                if [[ $event_epoch -ge $minute_ago ]]; then
                    # Check if it's an authentication request
                    if [[ "$event_type" == "request" && "$request_path" =~ auth.*login ]]; then
                        if [[ -n "$error" ]]; then
                            ((auth_failures++))
                            
                            # Track failed attempts by IP
                            if [[ -n "$client_ip" ]]; then
                                local ip_failures
                                ip_failures=$(grep -c "\"client_ip\":\"$client_ip\".*\"error\"" "$audit_log" 2>/dev/null || echo "0")
                                if [[ $ip_failures -gt 5 ]]; then
                                    suspicious_patterns+=("High failure rate from $client_ip: $ip_failures attempts")
                                fi
                            fi
                        else
                            ((auth_successes++))
                        fi
                        
                        # Track unique IPs
                        if [[ -n "$client_ip" ]] && [[ ! " ${unique_ips[*]} " =~ " $client_ip " ]]; then
                            unique_ips+=("$client_ip")
                        fi
                    fi
                fi
            fi
        fi
    done < <(tail -n 1000 "$audit_log")
    
    # Check thresholds
    local failed_auth_threshold=$(jq -r '.thresholds.failed_auth_per_minute' "$MONITOR_DIR/config.json")
    
    if [[ $auth_failures -gt $failed_auth_threshold ]]; then
        send_alert "HIGH" "High Authentication Failure Rate" \
            "Detected $auth_failures failed authentications in the last minute (threshold: $failed_auth_threshold)"
    fi
    
    # Alert on suspicious patterns
    for pattern in "${suspicious_patterns[@]}"; do
        send_alert "MEDIUM" "Suspicious Authentication Pattern" "$pattern"
    done
    
    # Log authentication metrics
    local auth_metrics=$(cat << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "time_window": "1_minute",
  "auth_failures": $auth_failures,
  "auth_successes": $auth_successes,
  "unique_ips": ${#unique_ips[@]},
  "suspicious_patterns": [$(printf '"%s",' "${suspicious_patterns[@]}" | sed 's/,$//')]
}
EOF
    )
    
    echo "$auth_metrics" >> "$METRICS_DIR/auth-metrics.log"
}

# Monitor token usage
monitor_token_usage() {
    local audit_log="/var/log/vault/audit/vault-audit.log"
    local now=$(date +%s)
    local minute_ago=$((now - 60))
    local token_creations=0
    local token_revocations=0
    local root_token_usage=0
    local unusual_patterns=()
    
    if [[ ! -f "$audit_log" ]]; then
        return 0
    fi
    
    # Analyze token-related events
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        local event_time event_type request_path operation client_ip token_policies
        if event_time=$(echo "$line" | jq -r '.time' 2>/dev/null) &&
           event_type=$(echo "$line" | jq -r '.type' 2>/dev/null) &&
           request_path=$(echo "$line" | jq -r '.request.path // ""' 2>/dev/null) &&
           operation=$(echo "$line" | jq -r '.request.operation // ""' 2>/dev/null) &&
           client_ip=$(echo "$line" | jq -r '.request.client_ip // ""' 2>/dev/null) &&
           token_policies=$(echo "$line" | jq -r '.auth.policies[]? // ""' 2>/dev/null); then
            
            local event_epoch
            if event_epoch=$(date -d "$event_time" +%s 2>/dev/null) && [[ $event_epoch -ge $minute_ago ]]; then
                # Token creation
                if [[ "$request_path" =~ auth/token/create ]]; then
                    ((token_creations++))
                fi
                
                # Token revocation
                if [[ "$request_path" =~ auth/token/revoke ]]; then
                    ((token_revocations++))
                fi
                
                # Root token usage
                if [[ "$token_policies" =~ root ]]; then
                    ((root_token_usage++))
                    
                    # Check for unusual root operations
                    if [[ ! "$request_path" =~ (sys/health|sys/seal-status|sys/leader) ]]; then
                        unusual_patterns+=("Root token used for: $operation on $request_path from $client_ip")
                    fi
                fi
            fi
        fi
    done < <(tail -n 1000 "$audit_log")
    
    # Check thresholds
    local token_creation_threshold=$(jq -r '.thresholds.token_creation_per_minute' "$MONITOR_DIR/config.json")
    
    if [[ $token_creations -gt $token_creation_threshold ]]; then
        send_alert "MEDIUM" "High Token Creation Rate" \
            "Detected $token_creations token creations in the last minute (threshold: $token_creation_threshold)"
    fi
    
    if [[ $root_token_usage -gt 0 ]]; then
        send_alert "HIGH" "Root Token Usage Detected" \
            "Root token used $root_token_usage times in the last minute"
    fi
    
    # Alert on unusual patterns
    for pattern in "${unusual_patterns[@]}"; do
        send_alert "HIGH" "Unusual Root Token Activity" "$pattern"
    done
    
    # Log token metrics
    local token_metrics=$(cat << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "time_window": "1_minute",
  "token_creations": $token_creations,
  "token_revocations": $token_revocations,
  "root_token_usage": $root_token_usage,
  "unusual_patterns": [$(printf '"%s",' "${unusual_patterns[@]}" | sed 's/,$//')]
}
EOF
    )
    
    echo "$token_metrics" >> "$METRICS_DIR/token-metrics.log"
}

# Monitor policy changes
monitor_policy_changes() {
    local audit_log="/var/log/vault/audit/vault-audit.log"
    local now=$(date +%s)
    local hour_ago=$((now - 3600))
    local policy_changes=0
    local auth_changes=0
    local mount_changes=0
    local critical_changes=()
    
    if [[ ! -f "$audit_log" ]]; then
        return 0
    fi
    
    # Analyze policy and configuration changes
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        local event_time event_type request_path operation client_ip
        if event_time=$(echo "$line" | jq -r '.time' 2>/dev/null) &&
           event_type=$(echo "$line" | jq -r '.type' 2>/dev/null) &&
           request_path=$(echo "$line" | jq -r '.request.path // ""' 2>/dev/null) &&
           operation=$(echo "$line" | jq -r '.request.operation // ""' 2>/dev/null) &&
           client_ip=$(echo "$line" | jq -r '.request.client_ip // ""' 2>/dev/null); then
            
            local event_epoch
            if event_epoch=$(date -d "$event_time" +%s 2>/dev/null) && [[ $event_epoch -ge $hour_ago ]]; then
                # Policy changes
                if [[ "$request_path" =~ sys/policy ]] && [[ "$operation" =~ (create|update|delete) ]]; then
                    ((policy_changes++))
                    critical_changes+=("Policy $operation: $request_path from $client_ip at $event_time")
                fi
                
                # Auth method changes
                if [[ "$request_path" =~ sys/auth ]] && [[ "$operation" =~ (create|update|delete) ]]; then
                    ((auth_changes++))
                    critical_changes+=("Auth method $operation: $request_path from $client_ip at $event_time")
                fi
                
                # Mount changes
                if [[ "$request_path" =~ sys/mounts ]] && [[ "$operation" =~ (create|update|delete) ]]; then
                    ((mount_changes++))
                    critical_changes+=("Secrets engine $operation: $request_path from $client_ip at $event_time")
                fi
            fi
        fi
    done < <(tail -n 2000 "$audit_log")
    
    # Check thresholds
    local privilege_threshold=$(jq -r '.thresholds.high_privilege_operations_per_hour' "$MONITOR_DIR/config.json")
    local total_critical=$((policy_changes + auth_changes + mount_changes))
    
    if [[ $total_critical -gt $privilege_threshold ]]; then
        send_alert "HIGH" "High Privilege Operation Rate" \
            "Detected $total_critical privileged operations in the last hour (threshold: $privilege_threshold)"
    fi
    
    # Alert on each critical change
    for change in "${critical_changes[@]}"; do
        send_alert "HIGH" "Critical Configuration Change" "$change"
    done
    
    # Log policy metrics
    local policy_metrics=$(cat << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "time_window": "1_hour",
  "policy_changes": $policy_changes,
  "auth_changes": $auth_changes,
  "mount_changes": $mount_changes,
  "total_critical_changes": $total_critical,
  "changes": [$(printf '"%s",' "${critical_changes[@]}" | sed 's/,$//')]
}
EOF
    )
    
    echo "$policy_metrics" >> "$METRICS_DIR/policy-metrics.log"
}

# Monitor performance metrics
monitor_performance() {
    local vault_pid
    local cpu_usage=0
    local memory_usage=0
    local response_time=0
    local disk_usage=0
    
    # Get Vault process ID
    if vault_pid=$(pgrep -f "vault server"); then
        # Get CPU and memory usage
        local ps_output
        if ps_output=$(ps -p "$vault_pid" -o %cpu,%mem --no-headers 2>/dev/null); then
            cpu_usage=$(echo "$ps_output" | awk '{print $1}' | sed 's/\..*//')
            memory_usage=$(echo "$ps_output" | awk '{print $2}' | sed 's/\..*//')
        fi
    fi
    
    # Test response time
    local start_time end_time
    start_time=$(date +%s%N)
    if curl -s -k "$VAULT_ADDR/v1/sys/health" >/dev/null; then
        end_time=$(date +%s%N)
        response_time=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds
    fi
    
    # Get disk usage for Vault data directory
    if [[ -d "/var/lib/vault" ]]; then
        disk_usage=$(df /var/lib/vault | tail -1 | awk '{print $5}' | sed 's/%//')
    fi
    
    # Check thresholds
    local cpu_threshold=$(jq -r '.thresholds.cpu_usage_percent' "$MONITOR_DIR/config.json")
    local memory_threshold=$(jq -r '.thresholds.memory_usage_percent' "$MONITOR_DIR/config.json")
    local response_threshold=$(jq -r '.thresholds.response_time_ms' "$MONITOR_DIR/config.json")
    local disk_threshold=$(jq -r '.thresholds.disk_usage_percent' "$MONITOR_DIR/config.json")
    
    # Check CPU usage
    if [[ $cpu_usage -gt $cpu_threshold ]]; then
        send_alert "MEDIUM" "High CPU Usage" \
            "Vault CPU usage: $cpu_usage% (threshold: $cpu_threshold%)"
    fi
    
    # Check memory usage
    if [[ $memory_usage -gt $memory_threshold ]]; then
        send_alert "MEDIUM" "High Memory Usage" \
            "Vault memory usage: $memory_usage% (threshold: $memory_threshold%)"
    fi
    
    # Check response time
    if [[ $response_time -gt $response_threshold ]]; then
        send_alert "MEDIUM" "Slow Response Time" \
            "Vault response time: ${response_time}ms (threshold: ${response_threshold}ms)"
    fi
    
    # Check disk usage
    if [[ $disk_usage -gt $disk_threshold ]]; then
        send_alert "HIGH" "High Disk Usage" \
            "Vault disk usage: $disk_usage% (threshold: $disk_threshold%)"
    fi
    
    # Log performance metrics
    local perf_metrics=$(cat << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "cpu_usage_percent": $cpu_usage,
  "memory_usage_percent": $memory_usage,
  "response_time_ms": $response_time,
  "disk_usage_percent": $disk_usage,
  "vault_pid": ${vault_pid:-0}
}
EOF
    )
    
    echo "$perf_metrics" >> "$METRICS_DIR/performance-metrics.log"
}

# Check certificate expiration
check_certificate_expiry() {
    local cert_file="/etc/vault.d/tls/vault-cert.pem"
    local warning_days=30
    
    if [[ ! -f "$cert_file" ]]; then
        send_alert "HIGH" "TLS Certificate Missing" "Vault TLS certificate not found: $cert_file"
        return 1
    fi
    
    # Get certificate expiration date
    local expiry_date
    if expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2 2>/dev/null); then
        local expiry_epoch current_epoch days_until_expiry
        expiry_epoch=$(date -d "$expiry_date" +%s)
        current_epoch=$(date +%s)
        days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
        
        if [[ $days_until_expiry -le 0 ]]; then
            send_alert "CRITICAL" "TLS Certificate Expired" \
                "Vault TLS certificate expired on $expiry_date"
        elif [[ $days_until_expiry -le $warning_days ]]; then
            send_alert "HIGH" "TLS Certificate Expiring Soon" \
                "Vault TLS certificate expires in $days_until_expiry days ($expiry_date)"
        fi
        
        # Log certificate status
        local cert_metrics=$(cat << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "certificate_file": "$cert_file",
  "expiry_date": "$expiry_date",
  "days_until_expiry": $days_until_expiry,
  "status": "$(if [[ $days_until_expiry -le 0 ]]; then echo "expired"; elif [[ $days_until_expiry -le $warning_days ]]; then echo "warning"; else echo "valid"; fi)"
}
EOF
        )
        
        echo "$cert_metrics" >> "$METRICS_DIR/certificate-metrics.log"
    else
        send_alert "HIGH" "Certificate Check Failed" "Unable to read certificate expiration date from $cert_file"
    fi
}

# Run all monitoring checks
run_monitoring_cycle() {
    log_step "Running security monitoring cycle..."
    
    local start_time=$(date +%s)
    local checks_passed=0
    local checks_failed=0
    
    # Run all checks
    local checks=(
        "check_vault_health"
        "monitor_authentication"
        "monitor_token_usage"
        "monitor_policy_changes"
        "monitor_performance"
        "check_certificate_expiry"
    )
    
    for check in "${checks[@]}"; do
        if $check; then
            ((checks_passed++))
        else
            ((checks_failed++))
        fi
    done
    
    local end_time=$(date +%s)
    local cycle_duration=$((end_time - start_time))
    
    # Log monitoring cycle summary
    local cycle_summary=$(cat << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "cycle_duration_seconds": $cycle_duration,
  "checks_passed": $checks_passed,
  "checks_failed": $checks_failed,
  "total_checks": ${#checks[@]}
}
EOF
    )
    
    echo "$cycle_summary" >> "$METRICS_DIR/monitoring-cycles.log"
    
    log_info "Monitoring cycle completed: $checks_passed passed, $checks_failed failed ($cycle_duration seconds)"
}

# Start continuous monitoring
start_monitoring() {
    log_step "Starting continuous security monitoring..."
    
    local interval=$(jq -r '.monitoring.interval' "$MONITOR_DIR/config.json")
    
    log_info "Monitoring interval: ${interval} seconds"
    log_info "Press Ctrl+C to stop monitoring"
    
    # Trap signals for graceful shutdown
    trap 'log_info "Stopping security monitoring..."; exit 0' INT TERM
    
    while true; do
        run_monitoring_cycle
        sleep "$interval"
    done
}

# Generate monitoring report
generate_monitoring_report() {
    local report_type="${1:-daily}"
    local output_file="$MONITOR_DIR/reports/monitoring-report-$report_type-$(date +%Y%m%d-%H%M%S).html"
    
    log_step "Generating $report_type monitoring report..."
    
    mkdir -p "$(dirname "$output_file")"
    
    # Calculate time range
    local hours
    case "$report_type" in
        "daily") hours=24 ;;
        "weekly") hours=168 ;;
        "monthly") hours=720 ;;
        *) hours=24 ;;
    esac
    
    local start_time=$(date -d "-$hours hours" +%s)
    
    # Generate HTML report
    cat > "$output_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Vault Security Monitoring Report - $report_type</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background-color: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .header { background-color: #1f2937; color: white; padding: 20px; border-radius: 5px; margin-bottom: 20px; }
        .section { margin: 20px 0; }
        .metric-card { display: inline-block; margin: 10px; padding: 15px; background-color: #e7f3ff; border-radius: 5px; min-width: 150px; text-align: center; }
        .metric-value { font-size: 2em; font-weight: bold; color: #1f2937; }
        .metric-label { color: #666; margin-top: 5px; }
        .alert { padding: 10px; margin: 5px 0; border-left: 4px solid; border-radius: 3px; }
        .alert-critical { border-left-color: #dc3545; background-color: #f8d7da; }
        .alert-high { border-left-color: #fd7e14; background-color: #fff3cd; }
        .alert-medium { border-left-color: #ffc107; background-color: #fff3cd; }
        .alert-low { border-left-color: #28a745; background-color: #d4edda; }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f8f9fa; }
        .chart { height: 300px; background-color: #f8f9fa; border: 1px solid #ddd; border-radius: 3px; display: flex; align-items: center; justify-content: center; color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🛡️ Vault Security Monitoring Report</h1>
            <p><strong>Report Type:</strong> $report_type | <strong>Generated:</strong> $(date) | <strong>Host:</strong> $(hostname)</p>
            <p><strong>Time Range:</strong> $(date -d "-$hours hours") to $(date)</p>
        </div>
        
        <div class="section">
            <h2>Executive Summary</h2>
            <div class="metric-card">
                <div class="metric-value">$(find "$ALERTS_DIR" -name "*.log" -newer <(date -d "-$hours hours") | wc -l)</div>
                <div class="metric-label">Total Alerts</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">$(find "$METRICS_DIR" -name "*.log" -newer <(date -d "-$hours hours") | wc -l)</div>
                <div class="metric-label">Monitoring Cycles</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">$(if systemctl is-active --quiet vault; then echo "🟢 UP"; else echo "🔴 DOWN"; fi)</div>
                <div class="metric-label">Vault Status</div>
            </div>
        </div>
        
        <div class="section">
            <h2>Recent Security Alerts</h2>
EOF
    
    # Add recent alerts
    if [[ -f "$ALERTS_DIR/security-alerts.log" ]]; then
        local alert_count=0
        while IFS= read -r alert_line && [[ $alert_count -lt 10 ]]; do
            if [[ -n "$alert_line" ]]; then
                local severity title message timestamp
                if severity=$(echo "$alert_line" | jq -r '.severity' 2>/dev/null) &&
                   title=$(echo "$alert_line" | jq -r '.title' 2>/dev/null) &&
                   message=$(echo "$alert_line" | jq -r '.message' 2>/dev/null) &&
                   timestamp=$(echo "$alert_line" | jq -r '.timestamp' 2>/dev/null); then
                    
                    local alert_class
                    case "$severity" in
                        "CRITICAL") alert_class="alert-critical" ;;
                        "HIGH") alert_class="alert-high" ;;
                        "MEDIUM") alert_class="alert-medium" ;;
                        "LOW") alert_class="alert-low" ;;
                        *) alert_class="alert-medium" ;;
                    esac
                    
                    cat >> "$output_file" << EOF
            <div class="alert $alert_class">
                <strong>[$severity] $title</strong><br>
                <small>$timestamp</small><br>
                $message
            </div>
EOF
                    ((alert_count++))
                fi
            fi
        done < <(tac "$ALERTS_DIR/security-alerts.log" 2>/dev/null || echo "")
        
        if [[ $alert_count -eq 0 ]]; then
            echo "            <p>No security alerts in the selected time range.</p>" >> "$output_file"
        fi
    else
        echo "            <p>No security alerts log found.</p>" >> "$output_file"
    fi
    
    # Add performance metrics section
    cat >> "$output_file" << 'EOF'
        </div>
        
        <div class="section">
            <h2>Performance Metrics</h2>
            <div class="chart">
                Performance charts would be displayed here with actual monitoring data
            </div>
        </div>
        
        <div class="section">
            <h2>Authentication Analytics</h2>
            <div class="chart">
                Authentication success/failure rates over time
            </div>
        </div>
        
        <div class="section">
            <h2>Recommendations</h2>
            <ul>
                <li>Review and investigate any CRITICAL or HIGH severity alerts</li>
                <li>Monitor authentication failure patterns for potential brute force attacks</li>
                <li>Ensure TLS certificates are renewed before expiration</li>
                <li>Review policy changes and ensure they are authorized</li>
                <li>Monitor resource usage trends for capacity planning</li>
            </ul>
        </div>
        
        <footer style="margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; text-align: center; color: #666;">
            <p><em>Report generated by Vault Security Monitoring System</em></p>
        </footer>
    </div>
</body>
</html>
EOF
    
    log_info "✅ Monitoring report generated: $output_file"
}

# Main function
main() {
    case "${1:-help}" in
        init)
            init_monitoring
            ;;
        start)
            start_monitoring
            ;;
        cycle)
            run_monitoring_cycle
            ;;
        report)
            generate_monitoring_report "${2:-daily}"
            ;;
        health)
            check_vault_health
            ;;
        auth)
            monitor_authentication
            ;;
        tokens)
            monitor_token_usage
            ;;
        policies)
            monitor_policy_changes
            ;;
        performance)
            monitor_performance
            ;;
        certificates)
            check_certificate_expiry
            ;;
        help|*)
            cat << EOF
Vault Security Monitoring System

Usage: $0 <command> [arguments]

Commands:
  init                    - Initialize monitoring system
  start                   - Start continuous monitoring
  cycle                   - Run single monitoring cycle
  report [type]           - Generate monitoring report (daily/weekly/monthly)
  health                  - Check Vault health only
  auth                    - Monitor authentication patterns only
  tokens                  - Monitor token usage only
  policies                - Monitor policy changes only
  performance             - Monitor performance metrics only
  certificates            - Check certificate expiry only
  help                    - Show this help message

Environment Variables:
  VAULT_ADDR              - Vault server address (default: https://127.0.0.1:8200)
  ALERT_EMAIL             - Email for alerts
  SLACK_WEBHOOK           - Slack webhook for alerts
  MONITORING_INTERVAL     - Monitoring interval in seconds (default: 60)
  THREAT_THRESHOLD        - Threat detection threshold (default: 5)

Examples:
  $0 init                 # Initialize monitoring system
  $0 start                # Start continuous monitoring
  $0 cycle                # Run single monitoring cycle
  $0 report weekly        # Generate weekly monitoring report
  
Monitoring Includes:
  - Vault health and availability
  - Authentication patterns and failures
  - Token usage and abuse detection
  - Policy and configuration changes
  - Performance metrics (CPU, memory, disk)
  - TLS certificate expiration
  - Security anomaly detection

Files Created:
  /var/log/vault/monitoring/     - Monitoring configuration
  /var/log/vault/metrics/        - Performance and security metrics
  /var/log/vault/alerts/         - Security alerts
EOF
            ;;
    esac
}

# Run main function with all arguments
main "$@"