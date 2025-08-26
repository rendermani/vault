#!/usr/bin/env bash
# Secret Rotation Automation
# Implements automated secret rotation with configurable TTLs and renewal policies
#
# This script addresses MEDIUM findings:
# - Missing secret rotation mechanisms
# - Lack of automated credential lifecycle management
# - No TTL policies for secrets

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="/var/log/cloudya-security"
VAULT_ADDR="${VAULT_ADDR:-https://vault.cloudya.net:8200}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[SECRET-ROTATION]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_DIR/secret-rotation.log"
}

log_success() {
    echo -e "${GREEN}[SECRET-ROTATION]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_DIR/secret-rotation.log"
}

log_error() {
    echo -e "${RED}[SECRET-ROTATION]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_DIR/secret-rotation.log" >&2
}

# Generate secure password with complexity requirements
generate_secure_password() {
    local length=${1:-32}
    local complexity=${2:-"high"}  # low, medium, high
    
    case $complexity in
        "low")
            # Alphanumeric only
            openssl rand -base64 $((length * 3 / 4)) | tr -d "=+/" | head -c$length
            ;;
        "medium")
            # Alphanumeric with some symbols
            openssl rand -base64 $((length * 3 / 4)) | tr -d "=" | head -c$length
            ;;
        "high")
            # Full complexity with symbols
            python3 -c "
import secrets
import string
length = $length
chars = string.ascii_letters + string.digits + '!@#$%^&*()_+-=[]{}|;:,.<>?'
password = ''.join(secrets.choice(chars) for _ in range(length))
print(password)
"
            ;;
        *)
            log_error "Invalid complexity level: $complexity"
            return 1
            ;;
    esac
}

# Generate bcrypt hash for passwords
generate_bcrypt_hash() {
    local password="$1"
    local rounds="${2:-12}"
    
    python3 -c "
import bcrypt
import sys
password = '$password'.encode('utf-8')
hashed = bcrypt.hashpw(password, bcrypt.gensalt(rounds=$rounds))
# Docker-compose requires \$\$ escaping
print(hashed.decode('utf-8').replace('\$', '\$\$'))
"
}

# Setup secret rotation policies in Vault
setup_rotation_policies() {
    log_info "Setting up secret rotation policies..."
    
    # Enable transit secrets engine for encryption
    vault secrets enable -path=transit transit 2>/dev/null || log_info "Transit engine already enabled"
    
    # Create encryption key for secret rotation
    vault write -f transit/keys/secret-rotation
    
    # Create rotation tracking KV store
    vault secrets enable -path=rotation kv-v2 2>/dev/null || log_info "Rotation tracking KV already enabled"
    
    # Database secrets engine for dynamic credentials
    vault secrets enable -path=database database 2>/dev/null || log_info "Database engine already enabled"
    
    log_success "Secret rotation policies configured"
}

# Configure dynamic database credentials
configure_database_rotation() {
    log_info "Configuring database credential rotation..."
    
    # PostgreSQL connection configuration
    vault write database/config/postgresql \
        plugin_name="postgresql-database-plugin" \
        connection_url="postgresql://{{username}}:{{password}}@postgres.service.consul:5432/postgres?sslmode=require" \
        allowed_roles="readonly,readwrite,admin" \
        username="vault" \
        password="$(generate_secure_password 24)"
    
    # Read-only role
    vault write database/roles/readonly \
        db_name="postgresql" \
        creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
            GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
        default_ttl="1h" \
        max_ttl="24h"
    
    # Read-write role
    vault write database/roles/readwrite \
        db_name="postgresql" \
        creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
            GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
        default_ttl="2h" \
        max_ttl="8h"
    
    # Admin role (limited use)
    vault write database/roles/admin \
        db_name="postgresql" \
        creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
            GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
        default_ttl="30m" \
        max_ttl="2h"
    
    log_success "Database credential rotation configured"
}

# Setup application secret rotation
setup_application_rotation() {
    log_info "Setting up application secret rotation..."
    
    # Create rotation schedules for different secret types
    local rotation_schedules=(
        "traefik_admin:24h:7d:high"      # service:default_ttl:max_ttl:complexity
        "grafana_admin:12h:24h:high"
        "prometheus_admin:24h:7d:medium"
        "consul_tokens:6h:24h:high"
        "nomad_tokens:8h:48h:high"
        "api_keys:1h:8h:high"
        "session_keys:30m:2h:high"
        "encryption_keys:7d:30d:high"
    )
    
    for schedule in "${rotation_schedules[@]}"; do
        IFS=':' read -r secret_name default_ttl max_ttl complexity <<< "$schedule"
        
        # Store rotation configuration
        vault kv put rotation/config/"$secret_name" \
            default_ttl="$default_ttl" \
            max_ttl="$max_ttl" \
            complexity="$complexity" \
            last_rotation="$(date -Iseconds)" \
            next_rotation="$(date -d "+$default_ttl" -Iseconds)" \
            rotation_count="0"
        
        log_info "Configured rotation for $secret_name (TTL: $default_ttl, Max: $max_ttl, Complexity: $complexity)"
    done
    
    log_success "Application secret rotation schedules configured"
}

# Create secret rotation engine
create_rotation_engine() {
    log_info "Creating secret rotation engine..."
    
    mkdir -p "$PROJECT_ROOT/automation/rotation-scripts"
    
    # Main rotation engine script
    cat > "$PROJECT_ROOT/automation/rotation-scripts/rotation-engine.sh" << 'EOF'
#!/usr/bin/env bash
# Secret Rotation Engine
# Automatically rotates secrets based on TTL policies

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-https://vault.cloudya.net:8200}"
LOG_FILE="/var/log/cloudya-security/rotation-engine.log"

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE" >&2
}

# Generate secure password
generate_secure_password() {
    local length=${1:-32}
    local complexity=${2:-"high"}
    
    case $complexity in
        "low")
            openssl rand -base64 $((length * 3 / 4)) | tr -d "=+/" | head -c$length
            ;;
        "medium")
            openssl rand -base64 $((length * 3 / 4)) | tr -d "=" | head -c$length
            ;;
        "high")
            python3 -c "
import secrets
import string
length = $length
chars = string.ascii_letters + string.digits + '!@#\$%^&*()_+-=[]{}|;:,.<>?'
password = ''.join(secrets.choice(chars) for _ in range(length))
print(password)
"
            ;;
    esac
}

# Generate bcrypt hash
generate_bcrypt_hash() {
    local password="$1"
    local rounds="${2:-12}"
    
    python3 -c "
import bcrypt
password = '$password'.encode('utf-8')
hashed = bcrypt.hashpw(password, bcrypt.gensalt(rounds=$rounds))
print(hashed.decode('utf-8').replace('\$', '\$\$'))
"
}

# Check if secret needs rotation
needs_rotation() {
    local secret_name="$1"
    
    # Get rotation config
    local config_json=$(vault kv get -format=json rotation/config/"$secret_name" 2>/dev/null) || return 1
    local next_rotation=$(echo "$config_json" | jq -r '.data.data.next_rotation')
    
    local next_timestamp=$(date -d "$next_rotation" +%s)
    local current_timestamp=$(date +%s)
    
    if [[ $current_timestamp -ge $next_timestamp ]]; then
        return 0  # Needs rotation
    else
        return 1  # No rotation needed
    fi
}

# Rotate application secret
rotate_application_secret() {
    local secret_name="$1"
    
    log_info "Rotating secret: $secret_name"
    
    # Get rotation configuration
    local config_json=$(vault kv get -format=json rotation/config/"$secret_name")
    local default_ttl=$(echo "$config_json" | jq -r '.data.data.default_ttl')
    local max_ttl=$(echo "$config_json" | jq -r '.data.data.max_ttl')
    local complexity=$(echo "$config_json" | jq -r '.data.data.complexity')
    local rotation_count=$(echo "$config_json" | jq -r '.data.data.rotation_count')
    
    # Generate new password
    local new_password=$(generate_secure_password 32 "$complexity")
    local new_hash=$(generate_bcrypt_hash "$new_password")
    
    # Store new secret
    case "$secret_name" in
        "traefik_admin")
            vault kv put secret/cloudya/traefik/admin \
                username="admin" \
                password="$new_password" \
                bcrypt_hash="$new_hash" \
                rotated_at="$(date -Iseconds)"
            ;;
        "grafana_admin")
            vault kv put secret/cloudya/grafana/admin \
                username="admin" \
                password="$new_password" \
                rotated_at="$(date -Iseconds)"
            ;;
        "prometheus_admin")
            vault kv put secret/cloudya/prometheus/admin \
                username="admin" \
                password="$new_password" \
                bcrypt_hash="$new_hash" \
                rotated_at="$(date -Iseconds)"
            ;;
        *)
            log_error "Unknown secret type: $secret_name"
            return 1
            ;;
    esac
    
    # Update rotation tracking
    vault kv put rotation/config/"$secret_name" \
        default_ttl="$default_ttl" \
        max_ttl="$max_ttl" \
        complexity="$complexity" \
        last_rotation="$(date -Iseconds)" \
        next_rotation="$(date -d "+$default_ttl" -Iseconds)" \
        rotation_count="$((rotation_count + 1))"
    
    log_success "Rotated secret: $secret_name (rotation #$((rotation_count + 1)))"
}

# Rotate all secrets that need it
rotate_secrets() {
    log_info "Checking secrets for rotation..."
    
    local secrets=$(vault kv list -format=json rotation/config/ | jq -r '.[]')
    local rotated_count=0
    
    for secret in $secrets; do
        if needs_rotation "$secret"; then
            rotate_application_secret "$secret"
            ((rotated_count++))
            
            # Trigger service restart if needed
            case "$secret" in
                "traefik_admin"|"prometheus_admin")
                    log_info "Triggering Vault Agent template refresh..."
                    systemctl reload vault-agent 2>/dev/null || log_error "Failed to reload Vault Agent"
                    ;;
                "grafana_admin")
                    log_info "Restarting Grafana service..."
                    docker-compose -f /opt/cloudya-infrastructure/docker-compose.production.yml restart grafana
                    ;;
            esac
        else
            log_info "Secret $secret does not need rotation yet"
        fi
    done
    
    log_info "Rotation check completed. Rotated $rotated_count secrets."
}

# Generate rotation report
generate_rotation_report() {
    log_info "Generating rotation report..."
    
    local report_file="/var/log/cloudya-security/rotation-report-$(date +%Y%m%d-%H%M%S).json"
    local secrets=$(vault kv list -format=json rotation/config/ 2>/dev/null | jq -r '.[]' || echo "")
    
    echo "{" > "$report_file"
    echo "  \"timestamp\": \"$(date -Iseconds)\"," >> "$report_file"
    echo "  \"secrets\": [" >> "$report_file"
    
    local first=true
    for secret in $secrets; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "    ," >> "$report_file"
        fi
        
        local config_json=$(vault kv get -format=json rotation/config/"$secret" 2>/dev/null)
        local last_rotation=$(echo "$config_json" | jq -r '.data.data.last_rotation')
        local next_rotation=$(echo "$config_json" | jq -r '.data.data.next_rotation')
        local rotation_count=$(echo "$config_json" | jq -r '.data.data.rotation_count')
        
        cat >> "$report_file" << EOF
    {
      "name": "$secret",
      "last_rotation": "$last_rotation",
      "next_rotation": "$next_rotation",
      "rotation_count": $rotation_count,
      "needs_rotation": $(needs_rotation "$secret" && echo "true" || echo "false")
    }
EOF
    done
    
    echo "  ]" >> "$report_file"
    echo "}" >> "$report_file"
    
    log_success "Rotation report generated: $report_file"
}

# Main execution
main() {
    local action="${1:-rotate}"
    
    case "$action" in
        "rotate")
            rotate_secrets
            ;;
        "report")
            generate_rotation_report
            ;;
        "check")
            log_info "Checking rotation status..."
            local secrets=$(vault kv list -format=json rotation/config/ 2>/dev/null | jq -r '.[]' || echo "")
            for secret in $secrets; do
                if needs_rotation "$secret"; then
                    echo "NEEDS ROTATION: $secret"
                else
                    echo "OK: $secret"
                fi
            done
            ;;
        *)
            echo "Usage: $0 {rotate|report|check}"
            exit 1
            ;;
    esac
}

main "$@"
EOF

    chmod +x "$PROJECT_ROOT/automation/rotation-scripts/rotation-engine.sh"
    
    log_success "Secret rotation engine created"
}

# Create token rotation scripts
create_token_rotation() {
    log_info "Creating token rotation scripts..."
    
    # Token rotation script
    cat > "$PROJECT_ROOT/automation/rotation-scripts/rotate-tokens.sh" << 'EOF'
#!/usr/bin/env bash
# Token Rotation Script
# Rotates Vault tokens with proper TTL management

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-https://vault.cloudya.net:8200}"
LOG_FILE="/var/log/cloudya-security/token-rotation.log"

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE" >&2
}

# Rotate service tokens
rotate_service_tokens() {
    log_info "Rotating service tokens..."
    
    # Get current service tokens
    local services=("traefik-secrets" "grafana-secrets" "prometheus-secrets" "consul-secrets")
    
    for service in "${services[@]}"; do
        log_info "Rotating token for $service..."
        
        # Create new token with same policies
        local policies=$(vault auth -method=token -field=policies "$service" 2>/dev/null || echo "$service")
        local new_token=$(vault write -field=token auth/token/create \
            policies="$policies" \
            ttl="24h" \
            renewable=true \
            display_name="$service-$(date +%s)")
        
        # Store new token
        vault kv put secret/cloudya/tokens/"$service" \
            token="$new_token" \
            created_at="$(date -Iseconds)" \
            ttl="24h"
        
        log_success "Token rotated for $service"
    done
}

# Rotate AppRole secret IDs
rotate_approle_secrets() {
    log_info "Rotating AppRole secret IDs..."
    
    local roles=$(vault list -format=json auth/approle/role/ 2>/dev/null | jq -r '.[]' || echo "")
    
    for role in $roles; do
        log_info "Rotating secret ID for AppRole: $role"
        
        # Generate new secret ID
        local new_secret_id=$(vault write -field=secret_id auth/approle/role/"$role"/secret-id)
        
        # Store new secret ID
        vault kv put secret/cloudya/approle/"$role" \
            secret_id="$new_secret_id" \
            created_at="$(date -Iseconds)"
        
        log_success "Secret ID rotated for AppRole: $role"
    done
}

# Main execution
main() {
    log_info "Starting token rotation..."
    
    rotate_service_tokens
    rotate_approle_secrets
    
    log_success "Token rotation completed"
}

main "$@"
EOF

    chmod +x "$PROJECT_ROOT/automation/rotation-scripts/rotate-tokens.sh"
    
    log_success "Token rotation scripts created"
}

# Setup rotation monitoring and alerting
setup_rotation_monitoring() {
    log_info "Setting up rotation monitoring and alerting..."
    
    # Rotation monitoring script
    cat > "$PROJECT_ROOT/automation/rotation-scripts/monitor-rotation.sh" << 'EOF'
#!/usr/bin/env bash
# Rotation Monitoring Script
# Monitors secret rotation health and sends alerts

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-https://vault.cloudya.net:8200}"
ALERT_EMAIL="${ALERT_EMAIL:-admin@cloudya.net}"
LOG_FILE="/var/log/cloudya-security/rotation-monitoring.log"

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE" >&2
}

# Send alert
send_alert() {
    local subject="$1"
    local message="$2"
    
    if command -v mail >/dev/null 2>&1; then
        echo "$message" | mail -s "$subject" "$ALERT_EMAIL"
        log_info "Alert sent: $subject"
    else
        log_error "Cannot send alert - mail command not available"
    fi
}

# Check rotation health
check_rotation_health() {
    log_info "Checking secret rotation health..."
    
    local issues=0
    local overdue_secrets=()
    
    # Check all configured secrets
    local secrets=$(vault kv list -format=json rotation/config/ 2>/dev/null | jq -r '.[]' || echo "")
    
    for secret in $secrets; do
        local config_json=$(vault kv get -format=json rotation/config/"$secret" 2>/dev/null)
        local next_rotation=$(echo "$config_json" | jq -r '.data.data.next_rotation')
        local max_ttl=$(echo "$config_json" | jq -r '.data.data.max_ttl')
        
        local next_timestamp=$(date -d "$next_rotation" +%s)
        local current_timestamp=$(date +%s)
        local max_overdue_timestamp=$(date -d "$next_rotation + $max_ttl" +%s)
        
        if [[ $current_timestamp -ge $max_overdue_timestamp ]]; then
            log_error "Secret critically overdue for rotation: $secret"
            overdue_secrets+=("$secret")
            ((issues++))
        elif [[ $current_timestamp -ge $next_timestamp ]]; then
            log_info "Secret due for rotation: $secret"
        fi
    done
    
    # Send alerts if needed
    if [[ $issues -gt 0 ]]; then
        local message="The following secrets are critically overdue for rotation:\n"
        for secret in "${overdue_secrets[@]}"; do
            message+="\n- $secret"
        done
        message+="\n\nPlease check the rotation system immediately."
        
        send_alert "Critical: Secret Rotation Overdue" "$message"
    fi
    
    log_info "Rotation health check completed. Issues: $issues"
    return $issues
}

# Check rotation system health
check_system_health() {
    log_info "Checking rotation system health..."
    
    # Check if Vault is accessible
    if ! vault status >/dev/null 2>&1; then
        send_alert "Rotation System Alert" "Vault is not accessible for secret rotation"
        return 1
    fi
    
    # Check if rotation engine is working
    if ! /opt/cloudya-infrastructure/automation/rotation-scripts/rotation-engine.sh check >/dev/null 2>&1; then
        send_alert "Rotation System Alert" "Rotation engine health check failed"
        return 1
    fi
    
    log_info "Rotation system is healthy"
    return 0
}

# Generate health report
generate_health_report() {
    log_info "Generating rotation health report..."
    
    local report_file="/var/log/cloudya-security/rotation-health-$(date +%Y%m%d-%H%M%S).json"
    
    cat > "$report_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "vault_status": $(vault status -format=json 2>/dev/null | jq .sealed || echo "null"),
  "rotation_engine_status": "$(if /opt/cloudya-infrastructure/automation/rotation-scripts/rotation-engine.sh check >/dev/null 2>&1; then echo 'healthy'; else echo 'error'; fi)",
  "secrets_status": [
EOF

    local secrets=$(vault kv list -format=json rotation/config/ 2>/dev/null | jq -r '.[]' || echo "")
    local first=true
    
    for secret in $secrets; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "    ," >> "$report_file"
        fi
        
        local config_json=$(vault kv get -format=json rotation/config/"$secret" 2>/dev/null)
        local next_rotation=$(echo "$config_json" | jq -r '.data.data.next_rotation')
        local rotation_count=$(echo "$config_json" | jq -r '.data.data.rotation_count')
        
        local next_timestamp=$(date -d "$next_rotation" +%s)
        local current_timestamp=$(date +%s)
        local status="ok"
        
        if [[ $current_timestamp -ge $next_timestamp ]]; then
            status="due"
        fi
        
        cat >> "$report_file" << EOF
    {
      "name": "$secret",
      "status": "$status",
      "next_rotation": "$next_rotation",
      "rotation_count": $rotation_count
    }
EOF
    done
    
    echo "  ]" >> "$report_file"
    echo "}" >> "$report_file"
    
    log_info "Health report generated: $report_file"
}

# Main execution
main() {
    local action="${1:-health}"
    
    case "$action" in
        "health")
            check_rotation_health
            check_system_health
            ;;
        "report")
            generate_health_report
            ;;
        *)
            echo "Usage: $0 {health|report}"
            exit 1
            ;;
    esac
}

main "$@"
EOF

    chmod +x "$PROJECT_ROOT/automation/rotation-scripts/monitor-rotation.sh"
    
    log_success "Rotation monitoring configured"
}

# Create systemd services for rotation
create_rotation_services() {
    log_info "Creating systemd services for rotation..."
    
    # Secret rotation service
    cat > /tmp/secret-rotation.service << 'EOF'
[Unit]
Description=CloudYa Secret Rotation
After=vault.service

[Service]
Type=oneshot
User=root
ExecStart=/opt/cloudya-infrastructure/automation/rotation-scripts/rotation-engine.sh rotate
StandardOutput=journal
StandardError=journal
EOF

    # Secret rotation timer (every 6 hours)
    cat > /tmp/secret-rotation.timer << 'EOF'
[Unit]
Description=Run CloudYa Secret Rotation Every 6 Hours
Requires=secret-rotation.service

[Timer]
OnCalendar=*-*-* 00,06,12,18:00:00
Persistent=true
RandomizedDelaySec=900

[Install]
WantedBy=timers.target
EOF

    # Token rotation service
    cat > /tmp/token-rotation.service << 'EOF'
[Unit]
Description=CloudYa Token Rotation
After=vault.service

[Service]
Type=oneshot
User=root
ExecStart=/opt/cloudya-infrastructure/automation/rotation-scripts/rotate-tokens.sh
StandardOutput=journal
StandardError=journal
EOF

    # Token rotation timer (daily)
    cat > /tmp/token-rotation.timer << 'EOF'
[Unit]
Description=Run CloudYa Token Rotation Daily
Requires=token-rotation.service

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=3600

[Install]
WantedBy=timers.target
EOF

    # Rotation monitoring service
    cat > /tmp/rotation-monitoring.service << 'EOF'
[Unit]
Description=CloudYa Rotation Monitoring
After=vault.service

[Service]
Type=oneshot
User=root
ExecStart=/opt/cloudya-infrastructure/automation/rotation-scripts/monitor-rotation.sh health
StandardOutput=journal
StandardError=journal
EOF

    # Rotation monitoring timer (every 2 hours)
    cat > /tmp/rotation-monitoring.timer << 'EOF'
[Unit]
Description=Run CloudYa Rotation Monitoring Every 2 Hours
Requires=rotation-monitoring.service

[Timer]
OnCalendar=*-*-* 00,02,04,06,08,10,12,14,16,18,20,22:00:00
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF

    # Install all services and timers
    for service in secret-rotation token-rotation rotation-monitoring; do
        sudo mv "/tmp/${service}.service" /etc/systemd/system/
        sudo mv "/tmp/${service}.timer" /etc/systemd/system/
        
        sudo systemctl daemon-reload
        sudo systemctl enable "${service}.timer"
        sudo systemctl start "${service}.timer"
        
        log_success "Installed and started ${service}.timer"
    done
    
    log_success "Rotation services configured and started"
}

# Main execution
main() {
    log_info "Starting secret rotation automation setup..."
    
    # Setup policies and engines
    setup_rotation_policies
    configure_database_rotation
    setup_application_rotation
    
    # Create rotation scripts
    create_rotation_engine
    create_token_rotation
    setup_rotation_monitoring
    
    # Setup systemd services
    create_rotation_services
    
    log_success "Secret rotation automation completed successfully!"
    log_info "Rotation engines are running with the following schedule:"
    log_info "  - Secret rotation: Every 6 hours"
    log_info "  - Token rotation: Daily"
    log_info "  - Monitoring: Every 2 hours"
    log_info "Logs are available in $LOG_DIR/"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi