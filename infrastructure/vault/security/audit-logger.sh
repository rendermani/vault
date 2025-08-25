#!/bin/bash

# Vault Audit Logging and Compliance System
# Comprehensive audit logging, monitoring, and compliance reporting

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT_DIR="/var/log/vault/audit"
COMPLIANCE_DIR="/var/log/vault/compliance"
ALERT_DIR="/var/log/vault/alerts"
VAULT_ADDR="${VAULT_ADDR:-https://127.0.0.1:8200}"
ALERT_EMAIL="${ALERT_EMAIL:-admin@cloudya.net}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"

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

# Initialize audit logging
init_audit_logging() {
    log_step "Initializing audit logging system..."
    
    # Create directories
    mkdir -p "$AUDIT_DIR" "$COMPLIANCE_DIR" "$ALERT_DIR"
    
    # Set proper permissions
    chmod 750 "$AUDIT_DIR" "$COMPLIANCE_DIR" "$ALERT_DIR"
    
    if id vault &>/dev/null; then
        chown -R vault:vault "$AUDIT_DIR" "$COMPLIANCE_DIR" "$ALERT_DIR"
    fi
    
    # Configure logrotate for audit logs
    cat > "/etc/logrotate.d/vault-audit" << 'EOF'
/var/log/vault/audit/*.log {
    daily
    rotate 365
    compress
    delaycompress
    notifempty
    create 640 vault vault
    postrotate
        systemctl reload vault || true
    endrotate
}

/var/log/vault/compliance/*.log {
    weekly
    rotate 52
    compress
    delaycompress
    notifempty
    create 640 vault vault
}

/var/log/vault/alerts/*.log {
    daily
    rotate 90
    compress
    delaycompress
    notifempty
    create 640 vault vault
}
EOF
    
    # Create rsyslog configuration for audit logs
    cat > "/etc/rsyslog.d/10-vault-audit.conf" << 'EOF'
# Vault audit logging
$template VaultAuditFormat,"%timestamp:::date-rfc3339% %hostname% vault-audit: %msg%\n"

# File audit device logs
if $programname == 'vault-audit-file' then {
    /var/log/vault/audit/file.log;VaultAuditFormat
    stop
}

# Syslog audit device logs
if $programname == 'vault-audit-syslog' then {
    /var/log/vault/audit/syslog.log;VaultAuditFormat
    stop
}

# Security events
if $programname == 'vault-security' then {
    /var/log/vault/alerts/security.log;VaultAuditFormat
    stop
}
EOF
    
    # Restart rsyslog to apply configuration
    systemctl restart rsyslog
    
    log_info "✅ Audit logging system initialized"
}

# Enable Vault audit devices
enable_audit_devices() {
    log_step "Enabling Vault audit devices..."
    
    # Check if we can connect to Vault
    if ! curl -s -k "$VAULT_ADDR/v1/sys/health" >/dev/null; then
        log_error "Cannot connect to Vault at $VAULT_ADDR"
        return 1
    fi
    
    # Load root token if available
    local token=""
    if [[ -f "/root/.vault/root-token" ]]; then
        token=$(cat /root/.vault/root-token)
    elif [[ -n "${VAULT_TOKEN:-}" ]]; then
        token="$VAULT_TOKEN"
    else
        log_error "No Vault token available. Please set VAULT_TOKEN or ensure root token file exists."
        return 1
    fi
    
    export VAULT_TOKEN="$token"
    
    # Enable file audit device
    log_step "Enabling file audit device..."
    vault audit enable -path="file" file file_path="/var/log/vault/audit/vault-audit.log" || {
        log_warn "File audit device may already be enabled"
    }
    
    # Enable syslog audit device
    log_step "Enabling syslog audit device..."
    vault audit enable -path="syslog" syslog facility="AUTH" tag="vault-audit" || {
        log_warn "Syslog audit device may already be enabled"
    }
    
    # Enable socket audit device for real-time monitoring
    log_step "Enabling socket audit device..."
    vault audit enable -path="socket" socket address="127.0.0.1:9090" socket_type="tcp" || {
        log_warn "Socket audit device may already be enabled"
    }
    
    log_info "✅ Audit devices enabled"
}

# Create audit analysis tools
create_audit_analyzer() {
    log_step "Creating audit analysis tools..."
    
    # Create audit log parser script
    cat > "/usr/local/bin/vault-audit-parser.py" << 'EOF'
#!/usr/bin/env python3
"""
Vault Audit Log Parser and Analyzer
Parses Vault audit logs and generates insights
"""

import json
import sys
import argparse
from datetime import datetime, timedelta
from collections import defaultdict, Counter
import re

class VaultAuditAnalyzer:
    def __init__(self, log_file):
        self.log_file = log_file
        self.events = []
        self.load_events()
    
    def load_events(self):
        """Load and parse audit events from log file"""
        try:
            with open(self.log_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    
                    try:
                        # Parse JSON audit event
                        event = json.loads(line)
                        self.events.append(event)
                    except json.JSONDecodeError:
                        # Handle non-JSON lines (e.g., from syslog format)
                        if 'vault-audit:' in line:
                            json_part = line.split('vault-audit: ', 1)[1]
                            try:
                                event = json.loads(json_part)
                                self.events.append(event)
                            except json.JSONDecodeError:
                                continue
        except FileNotFoundError:
            print(f"Error: Audit log file not found: {self.log_file}")
            sys.exit(1)
    
    def analyze_authentication(self):
        """Analyze authentication patterns"""
        auth_events = [e for e in self.events if e.get('type') == 'request' and 'auth' in e.get('request', {}).get('path', '')]
        
        if not auth_events:
            return {"message": "No authentication events found"}
        
        auth_methods = Counter()
        success_count = 0
        failure_count = 0
        unique_clients = set()
        
        for event in auth_events:
            # Count authentication methods
            path = event.get('request', {}).get('path', '')
            if '/login' in path:
                method = path.split('/')[1] if '/' in path else 'unknown'
                auth_methods[method] += 1
            
            # Count success/failure
            error = event.get('error', '')
            if error:
                failure_count += 1
            else:
                success_count += 1
            
            # Track unique clients
            client_ip = event.get('request', {}).get('client_ip', '')
            if client_ip:
                unique_clients.add(client_ip)
        
        return {
            "total_auth_attempts": len(auth_events),
            "successful_auths": success_count,
            "failed_auths": failure_count,
            "success_rate": f"{(success_count / len(auth_events) * 100):.2f}%",
            "auth_methods": dict(auth_methods.most_common()),
            "unique_clients": len(unique_clients),
            "top_client_ips": list(unique_clients)[:10]
        }
    
    def analyze_secrets_access(self):
        """Analyze secrets access patterns"""
        secret_events = [e for e in self.events if e.get('type') == 'request' and 'secret' in e.get('request', {}).get('path', '')]
        
        if not secret_events:
            return {"message": "No secrets access events found"}
        
        operations = Counter()
        secret_paths = Counter()
        clients = Counter()
        
        for event in secret_events:
            # Count operations
            operation = event.get('request', {}).get('operation', 'unknown')
            operations[operation] += 1
            
            # Count secret paths
            path = event.get('request', {}).get('path', '')
            secret_paths[path] += 1
            
            # Count clients
            client_ip = event.get('request', {}).get('client_ip', '')
            if client_ip:
                clients[client_ip] += 1
        
        return {
            "total_secret_accesses": len(secret_events),
            "operations": dict(operations.most_common()),
            "most_accessed_paths": dict(secret_paths.most_common(10)),
            "top_clients": dict(clients.most_common(10))
        }
    
    def detect_anomalies(self):
        """Detect security anomalies"""
        anomalies = []
        
        # Detect brute force attempts
        failed_auths = defaultdict(list)
        for event in self.events:
            if event.get('error') and 'auth' in event.get('request', {}).get('path', ''):
                client_ip = event.get('request', {}).get('client_ip', '')
                timestamp = event.get('time', '')
                if client_ip:
                    failed_auths[client_ip].append(timestamp)
        
        for ip, failures in failed_auths.items():
            if len(failures) > 10:  # More than 10 failed attempts
                anomalies.append({
                    "type": "potential_brute_force",
                    "client_ip": ip,
                    "failed_attempts": len(failures),
                    "severity": "high"
                })
        
        # Detect unusual access patterns
        access_counts = Counter()
        for event in self.events:
            if event.get('type') == 'request':
                client_ip = event.get('request', {}).get('client_ip', '')
                if client_ip:
                    access_counts[client_ip] += 1
        
        # Find clients with unusually high access
        if access_counts:
            avg_access = sum(access_counts.values()) / len(access_counts)
            threshold = avg_access * 5  # 5x average
            
            for ip, count in access_counts.items():
                if count > threshold:
                    anomalies.append({
                        "type": "high_volume_access",
                        "client_ip": ip,
                        "access_count": count,
                        "average": avg_access,
                        "severity": "medium"
                    })
        
        # Detect privileged operations
        for event in self.events:
            path = event.get('request', {}).get('path', '')
            operation = event.get('request', {}).get('operation', '')
            
            if any(priv in path for priv in ['sys/auth', 'sys/policy', 'sys/mount']):
                if operation in ['create', 'update', 'delete']:
                    anomalies.append({
                        "type": "privileged_operation",
                        "path": path,
                        "operation": operation,
                        "client_ip": event.get('request', {}).get('client_ip', ''),
                        "time": event.get('time', ''),
                        "severity": "high"
                    })
        
        return anomalies
    
    def generate_compliance_report(self):
        """Generate compliance report"""
        total_events = len(self.events)
        if total_events == 0:
            return {"message": "No events to analyze"}
        
        # Get date range
        timestamps = [e.get('time', '') for e in self.events if e.get('time')]
        date_range = {
            "start": min(timestamps) if timestamps else "Unknown",
            "end": max(timestamps) if timestamps else "Unknown",
            "total_events": total_events
        }
        
        # Analyze by event types
        event_types = Counter([e.get('type', 'unknown') for e in self.events])
        
        # Analyze by operations
        operations = Counter([e.get('request', {}).get('operation', 'unknown') for e in self.events if e.get('type') == 'request'])
        
        # Security metrics
        failed_requests = len([e for e in self.events if e.get('error')])
        success_rate = ((total_events - failed_requests) / total_events * 100) if total_events > 0 else 0
        
        return {
            "report_generated": datetime.now().isoformat(),
            "date_range": date_range,
            "summary": {
                "total_events": total_events,
                "success_rate": f"{success_rate:.2f}%",
                "failed_requests": failed_requests
            },
            "event_types": dict(event_types),
            "operations": dict(operations.most_common(10)),
            "authentication_analysis": self.analyze_authentication(),
            "secrets_analysis": self.analyze_secrets_access(),
            "anomalies": self.detect_anomalies()
        }

def main():
    parser = argparse.ArgumentParser(description='Vault Audit Log Analyzer')
    parser.add_argument('log_file', help='Path to vault audit log file')
    parser.add_argument('--format', choices=['json', 'summary'], default='summary', help='Output format')
    parser.add_argument('--output', help='Output file (default: stdout)')
    
    args = parser.parse_args()
    
    analyzer = VaultAuditAnalyzer(args.log_file)
    report = analyzer.generate_compliance_report()
    
    if args.format == 'json':
        output = json.dumps(report, indent=2)
    else:
        # Generate human-readable summary
        output = f"""
Vault Audit Analysis Report
==========================

Report Generated: {report.get('report_generated', 'Unknown')}
Analysis Period: {report.get('date_range', {}).get('start', 'Unknown')} to {report.get('date_range', {}).get('end', 'Unknown')}

Summary:
  Total Events: {report.get('summary', {}).get('total_events', 0)}
  Success Rate: {report.get('summary', {}).get('success_rate', 'N/A')}
  Failed Requests: {report.get('summary', {}).get('failed_requests', 0)}

Authentication Analysis:
  Total Attempts: {report.get('authentication_analysis', {}).get('total_auth_attempts', 0)}
  Success Rate: {report.get('authentication_analysis', {}).get('success_rate', 'N/A')}
  Unique Clients: {report.get('authentication_analysis', {}).get('unique_clients', 0)}

Security Anomalies: {len(report.get('anomalies', []))}
"""
        
        anomalies = report.get('anomalies', [])
        if anomalies:
            output += "\nSecurity Anomalies:\n"
            for anomaly in anomalies[:10]:  # Show top 10
                output += f"  - {anomaly.get('type', 'Unknown')}: {anomaly.get('severity', 'unknown')} severity\n"
    
    if args.output:
        with open(args.output, 'w') as f:
            f.write(output)
        print(f"Report written to: {args.output}")
    else:
        print(output)

if __name__ == '__main__':
    main()
EOF
    
    chmod +x "/usr/local/bin/vault-audit-parser.py"
    
    log_info "✅ Audit analysis tools created"
}

# Setup real-time monitoring
setup_realtime_monitoring() {
    log_step "Setting up real-time audit monitoring..."
    
    # Create systemd service for real-time monitoring
    cat > "/etc/systemd/system/vault-audit-monitor.service" << 'EOF'
[Unit]
Description=Vault Audit Real-time Monitor
After=network.target vault.service
Requires=vault.service

[Service]
Type=simple
User=vault
Group=vault
ExecStart=/usr/local/bin/vault-audit-monitor.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # Create monitoring script
    cat > "/usr/local/bin/vault-audit-monitor.sh" << 'EOF'
#!/bin/bash

# Real-time Vault audit log monitor
set -euo pipefail

AUDIT_LOG="/var/log/vault/audit/vault-audit.log"
ALERT_DIR="/var/log/vault/alerts"
ALERT_EMAIL="${ALERT_EMAIL:-admin@cloudya.net}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"

log_alert() {
    local severity="$1"
    local message="$2"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Log to file
    echo "[$timestamp] [$severity] $message" >> "$ALERT_DIR/realtime-alerts.log"
    
    # Send email alert
    if command -v mail >/dev/null && [[ -n "$ALERT_EMAIL" ]]; then
        echo "$message" | mail -s "Vault Security Alert - $severity" "$ALERT_EMAIL"
    fi
    
    # Send Slack alert
    if [[ -n "$SLACK_WEBHOOK" ]]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"🚨 Vault Alert [$severity]: $message\"}" \
            "$SLACK_WEBHOOK" >/dev/null 2>&1 || true
    fi
}

monitor_audit_log() {
    if [[ ! -f "$AUDIT_LOG" ]]; then
        echo "Audit log not found: $AUDIT_LOG"
        exit 1
    fi
    
    echo "Starting real-time audit monitoring..."
    
    # Monitor with tail and process each line
    tail -F "$AUDIT_LOG" | while read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue
        
        # Parse JSON
        if ! event=$(echo "$line" | jq . 2>/dev/null); then
            continue
        fi
        
        # Extract key fields
        event_type=$(echo "$event" | jq -r '.type // "unknown"')
        error=$(echo "$event" | jq -r '.error // ""')
        path=$(echo "$event" | jq -r '.request.path // ""')
        operation=$(echo "$event" | jq -r '.request.operation // ""')
        client_ip=$(echo "$event" | jq -r '.request.client_ip // ""')
        
        # Check for security events
        
        # Failed authentication
        if [[ "$error" != "" && "$path" =~ auth.*login ]]; then
            log_alert "HIGH" "Failed authentication from $client_ip to $path: $error"
        fi
        
        # Root token usage
        if [[ "$path" =~ sys/(auth|policy|mount) && "$operation" =~ (create|update|delete) ]]; then
            log_alert "CRITICAL" "Privileged operation: $operation on $path from $client_ip"
        fi
        
        # Seal/unseal operations
        if [[ "$path" =~ sys/seal ]]; then
            log_alert "CRITICAL" "Seal operation: $operation on $path from $client_ip"
        fi
        
        # Policy modifications
        if [[ "$path" =~ sys/policy && "$operation" =~ (create|update|delete) ]]; then
            log_alert "HIGH" "Policy modification: $operation on $path from $client_ip"
        fi
        
        # Auth method changes
        if [[ "$path" =~ sys/auth && "$operation" =~ (create|update|delete) ]]; then
            log_alert "HIGH" "Auth method change: $operation on $path from $client_ip"
        fi
    done
}

# Main monitoring loop with error handling
while true; do
    monitor_audit_log || {
        echo "Monitor failed, restarting in 10 seconds..."
        sleep 10
    }
done
EOF
    
    chmod +x "/usr/local/bin/vault-audit-monitor.sh"
    
    # Enable and start the service
    systemctl daemon-reload
    systemctl enable vault-audit-monitor.service
    systemctl start vault-audit-monitor.service
    
    log_info "✅ Real-time audit monitoring enabled"
}

# Generate compliance reports
generate_compliance_report() {
    local report_type="${1:-daily}"
    local output_dir="$COMPLIANCE_DIR/reports"
    
    log_step "Generating $report_type compliance report..."
    
    mkdir -p "$output_dir"
    
    local report_name="vault-compliance-$report_type-$(date +%Y%m%d-%H%M%S)"
    local audit_log="/var/log/vault/audit/vault-audit.log"
    
    if [[ ! -f "$audit_log" ]]; then
        log_error "Audit log not found: $audit_log"
        return 1
    fi
    
    # Generate JSON report
    /usr/local/bin/vault-audit-parser.py "$audit_log" \
        --format json \
        --output "$output_dir/$report_name.json"
    
    # Generate summary report
    /usr/local/bin/vault-audit-parser.py "$audit_log" \
        --format summary \
        --output "$output_dir/$report_name.txt"
    
    # Create HTML report
    create_html_report "$output_dir/$report_name.json" "$output_dir/$report_name.html"
    
    log_info "✅ Compliance report generated: $output_dir/$report_name"
}

# Create HTML compliance report
create_html_report() {
    local json_file="$1"
    local html_file="$2"
    
    if [[ ! -f "$json_file" ]]; then
        log_error "JSON report not found: $json_file"
        return 1
    fi
    
    local report_data=$(cat "$json_file")
    
    cat > "$html_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Vault Compliance Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }
        .section { margin: 20px 0; }
        .metric { display: inline-block; margin: 10px; padding: 10px; background-color: #e7f3ff; border-radius: 3px; }
        .anomaly { background-color: #ffebee; border-left: 4px solid #f44336; padding: 10px; margin: 5px 0; }
        .high { border-left-color: #f44336; }
        .medium { border-left-color: #ff9800; }
        .low { border-left-color: #4caf50; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Vault Security Compliance Report</h1>
        <p><strong>Generated:</strong> $(echo "$report_data" | jq -r '.report_generated')</p>
        <p><strong>Period:</strong> $(echo "$report_data" | jq -r '.date_range.start') to $(echo "$report_data" | jq -r '.date_range.end')</p>
    </div>
    
    <div class="section">
        <h2>Summary Metrics</h2>
        <div class="metric">
            <strong>Total Events:</strong> $(echo "$report_data" | jq -r '.summary.total_events')
        </div>
        <div class="metric">
            <strong>Success Rate:</strong> $(echo "$report_data" | jq -r '.summary.success_rate')
        </div>
        <div class="metric">
            <strong>Failed Requests:</strong> $(echo "$report_data" | jq -r '.summary.failed_requests')
        </div>
    </div>
    
    <div class="section">
        <h2>Authentication Analysis</h2>
        <p><strong>Total Auth Attempts:</strong> $(echo "$report_data" | jq -r '.authentication_analysis.total_auth_attempts // 0')</p>
        <p><strong>Success Rate:</strong> $(echo "$report_data" | jq -r '.authentication_analysis.success_rate // "N/A"')</p>
        <p><strong>Unique Clients:</strong> $(echo "$report_data" | jq -r '.authentication_analysis.unique_clients // 0')</p>
    </div>
    
    <div class="section">
        <h2>Security Anomalies</h2>
EOF
    
    # Add anomalies to HTML
    echo "$report_data" | jq -r '.anomalies[]' | while IFS= read -r anomaly; do
        local severity=$(echo "$anomaly" | jq -r '.severity')
        local type=$(echo "$anomaly" | jq -r '.type')
        local details=$(echo "$anomaly" | jq -r '. | to_entries | map("\(.key): \(.value)") | join(", ")')
        
        echo "        <div class=\"anomaly $severity\">" >> "$html_file"
        echo "            <strong>$type</strong> ($severity): $details" >> "$html_file"
        echo "        </div>" >> "$html_file"
    done
    
    cat >> "$html_file" << 'EOF'
    </div>
    
    <div class="section">
        <h2>Operations Summary</h2>
        <table>
            <tr><th>Operation</th><th>Count</th></tr>
EOF
    
    # Add operations table
    echo "$report_data" | jq -r '.operations | to_entries[] | "\(.key):\(.value)"' | while IFS=: read -r operation count; do
        echo "            <tr><td>$operation</td><td>$count</td></tr>" >> "$html_file"
    done
    
    cat >> "$html_file" << 'EOF'
        </table>
    </div>
    
    <footer>
        <p><em>Report generated by Vault Audit System</em></p>
    </footer>
</body>
</html>
EOF
}

# Setup automated reporting
setup_automated_reporting() {
    log_step "Setting up automated compliance reporting..."
    
    # Create daily report cron job
    cat > "/etc/cron.d/vault-compliance-reports" << 'EOF'
# Vault compliance reporting schedule
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin

# Daily report at 2 AM
0 2 * * * root /usr/local/bin/vault-audit-logger.sh report daily >/dev/null 2>&1

# Weekly report on Sundays at 3 AM  
0 3 * * 0 root /usr/local/bin/vault-audit-logger.sh report weekly >/dev/null 2>&1

# Monthly report on the 1st at 4 AM
0 4 1 * * root /usr/local/bin/vault-audit-logger.sh report monthly >/dev/null 2>&1
EOF
    
    # Restart cron to pick up new jobs
    systemctl restart cron || systemctl restart crond || true
    
    log_info "✅ Automated compliance reporting configured"
}

# Check audit log integrity
check_log_integrity() {
    log_step "Checking audit log integrity..."
    
    local audit_log="/var/log/vault/audit/vault-audit.log"
    local errors=0
    
    if [[ ! -f "$audit_log" ]]; then
        log_error "Audit log not found: $audit_log"
        return 1
    fi
    
    # Check file permissions
    local perms=$(stat -c "%a" "$audit_log")
    if [[ "$perms" != "640" ]]; then
        log_warn "Audit log has incorrect permissions: $perms (should be 640)"
        ((errors++))
    fi
    
    # Check file ownership
    local owner=$(stat -c "%U:%G" "$audit_log")
    if [[ "$owner" != "vault:vault" ]]; then
        log_warn "Audit log has incorrect ownership: $owner (should be vault:vault)"
        ((errors++))
    fi
    
    # Check for JSON format validity
    local total_lines=$(wc -l < "$audit_log")
    local valid_json=0
    local invalid_lines=()
    
    local line_count=0
    while IFS= read -r line; do
        ((line_count++))
        [[ -z "$line" ]] && continue
        
        if echo "$line" | jq . >/dev/null 2>&1; then
            ((valid_json++))
        else
            invalid_lines+=("$line_count")
        fi
        
        # Limit checking to avoid long processing
        if [[ $line_count -gt 1000 ]]; then
            break
        fi
    done < "$audit_log"
    
    local validity_percent=$((valid_json * 100 / line_count))
    
    log_info "Audit log statistics:"
    log_info "  Total lines checked: $line_count"
    log_info "  Valid JSON entries: $valid_json"
    log_info "  Validity percentage: $validity_percent%"
    
    if [[ $validity_percent -lt 90 ]]; then
        log_warn "Low JSON validity percentage: $validity_percent%"
        ((errors++))
    fi
    
    if [[ ${#invalid_lines[@]} -gt 0 ]]; then
        log_warn "Invalid JSON found on lines: ${invalid_lines[*]:0:10}"
    fi
    
    # Check disk space
    local disk_usage=$(df $(dirname "$audit_log") | tail -1 | awk '{print $5}' | sed 's/%//')
    log_info "Audit log disk usage: $disk_usage%"
    
    if [[ $disk_usage -gt 80 ]]; then
        log_warn "High disk usage for audit logs: $disk_usage%"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_info "✅ Audit log integrity check passed"
        return 0
    else
        log_error "❌ Audit log integrity check failed with $errors issues"
        return 1
    fi
}

# Archive old audit logs
archive_old_logs() {
    local retention_days="${1:-90}"
    
    log_step "Archiving audit logs older than $retention_days days..."
    
    local archive_dir="/var/log/vault/archive"
    mkdir -p "$archive_dir"
    
    # Find and archive old logs
    find "$AUDIT_DIR" -name "*.log" -type f -mtime +$retention_days | while read -r log_file; do
        local basename=$(basename "$log_file")
        local archive_name="$archive_dir/${basename%.log}-$(date +%Y%m%d).tar.gz"
        
        tar -czf "$archive_name" "$log_file" && rm -f "$log_file"
        log_info "Archived: $basename -> $archive_name"
    done
    
    # Clean up very old archives (1 year)
    find "$archive_dir" -name "*.tar.gz" -type f -mtime +365 -delete
    
    log_info "✅ Log archival completed"
}

# Main function
main() {
    case "${1:-help}" in
        init)
            init_audit_logging
            ;;
        enable)
            enable_audit_devices
            ;;
        setup-tools)
            create_audit_analyzer
            ;;
        monitor)
            setup_realtime_monitoring
            ;;
        report)
            generate_compliance_report "${2:-daily}"
            ;;
        setup-reporting)
            setup_automated_reporting
            ;;
        check-integrity)
            check_log_integrity
            ;;
        archive)
            archive_old_logs "${2:-90}"
            ;;
        full-setup)
            init_audit_logging
            enable_audit_devices
            create_audit_analyzer
            setup_realtime_monitoring
            setup_automated_reporting
            ;;
        help|*)
            cat << EOF
Vault Audit Logging and Compliance System

Usage: $0 <command> [arguments]

Commands:
  init                    - Initialize audit logging directories and configuration
  enable                  - Enable Vault audit devices (file, syslog, socket)
  setup-tools             - Create audit analysis tools
  monitor                 - Setup real-time audit monitoring
  report [type]           - Generate compliance report (daily/weekly/monthly)
  setup-reporting         - Setup automated compliance reporting
  check-integrity         - Check audit log integrity
  archive [days]          - Archive logs older than N days (default: 90)
  full-setup              - Run complete audit logging setup
  help                    - Show this help message

Environment Variables:
  VAULT_ADDR         - Vault server address (default: https://127.0.0.1:8200)
  VAULT_TOKEN        - Vault authentication token
  ALERT_EMAIL        - Email for security alerts
  SLACK_WEBHOOK      - Slack webhook for alerts

Examples:
  $0 full-setup                     # Complete audit setup
  $0 enable                         # Enable audit devices
  $0 report daily                   # Generate daily compliance report
  $0 check-integrity                # Check log integrity
  $0 archive 60                     # Archive logs older than 60 days

Files Created:
  /var/log/vault/audit/             - Audit logs
  /var/log/vault/compliance/        - Compliance reports  
  /var/log/vault/alerts/            - Security alerts
  /usr/local/bin/vault-audit-parser.py - Log analysis tool
EOF
            ;;
    esac
}

# Run main function with all arguments
main "$@"