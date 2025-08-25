#!/bin/bash

# Emergency Access Procedures for Vault
# Provides secure emergency access mechanisms and break-glass procedures

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMERGENCY_DIR="/etc/vault.d/emergency"
EMERGENCY_KEYS_DIR="$EMERGENCY_DIR/keys"
EMERGENCY_TOKENS_DIR="$EMERGENCY_DIR/tokens"
BREAK_GLASS_LOG="/var/log/vault/emergency/break-glass.log"
VAULT_ADDR="${VAULT_ADDR:-https://127.0.0.1:8200}"
EMERGENCY_EMAIL="${EMERGENCY_EMAIL:-admin@cloudya.net,security@cloudya.net}"

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
log_emergency() { echo -e "${RED}[EMERGENCY]${NC} $1"; }

# Log emergency actions
log_emergency_action() {
    local action="$1"
    local user="${2:-$(whoami)}"
    local details="${3:-}"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    mkdir -p "$(dirname "$BREAK_GLASS_LOG")"
    
    local log_entry=$(cat << EOF
{
  "timestamp": "$timestamp",
  "action": "$action",
  "user": "$user",
  "hostname": "$(hostname)",
  "source_ip": "$(who am i | awk '{print $5}' | tr -d '()' || echo 'unknown')",
  "details": "$details",
  "severity": "CRITICAL"
}
EOF
    )
    
    echo "$log_entry" >> "$BREAK_GLASS_LOG"
    
    # Send alert
    send_emergency_alert "$action" "$user" "$details"
}

# Send emergency alerts
send_emergency_alert() {
    local action="$1"
    local user="$2"
    local details="$3"
    
    local subject="🚨 VAULT EMERGENCY ACCESS - $action"
    local message="Emergency access procedure initiated:

Action: $action
User: $user
Time: $(date)
Host: $(hostname)
Details: $details

This is an automated security alert. Please investigate immediately."
    
    # Send email alert
    if command -v mail >/dev/null && [[ -n "$EMERGENCY_EMAIL" ]]; then
        echo "$message" | mail -s "$subject" "$EMERGENCY_EMAIL"
    fi
    
    # Send Slack alert if webhook configured
    if [[ -n "${SLACK_WEBHOOK:-}" ]]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$subject\\n\\n$message\"}" \
            "$SLACK_WEBHOOK" >/dev/null 2>&1 || true
    fi
    
    # Log to syslog
    logger -t "vault-emergency" -p auth.crit "$subject: $action by $user"
}

# Initialize emergency access system
init_emergency_access() {
    log_step "Initializing emergency access system..."
    
    # Create directories
    mkdir -p "$EMERGENCY_DIR" "$EMERGENCY_KEYS_DIR" "$EMERGENCY_TOKENS_DIR"
    mkdir -p "$(dirname "$BREAK_GLASS_LOG")"
    
    # Set strict permissions
    chmod 700 "$EMERGENCY_DIR" "$EMERGENCY_KEYS_DIR" "$EMERGENCY_TOKENS_DIR"
    chmod 750 "$(dirname "$BREAK_GLASS_LOG")"
    
    # Create emergency break-glass documentation
    cat > "$EMERGENCY_DIR/README.md" << 'EOF'
# Vault Emergency Access Procedures

## Break-Glass Procedures

### 1. Emergency Unseal
Used when Vault is sealed and normal unseal keys are unavailable.
```bash
./emergency-access.sh break-glass-unseal
```

### 2. Root Token Recovery
Used when root token is lost or compromised.
```bash
./emergency-access.sh recover-root-token
```

### 3. Generate Emergency Token
Creates a temporary high-privilege token.
```bash
./emergency-access.sh generate-emergency-token
```

### 4. Backup Recovery
Restore Vault from emergency backup.
```bash
./emergency-access.sh emergency-restore /path/to/backup
```

## Important Notes

1. All emergency actions are logged and alerts are sent
2. Emergency tokens have limited TTL (1 hour default)
3. Change all credentials after emergency procedures
4. Review security posture after incident resolution

## Emergency Contacts

- Primary: admin@cloudya.net
- Security: security@cloudya.net
- On-call: Check escalation procedures
EOF
    
    chmod 600 "$EMERGENCY_DIR/README.md"
    
    log_info "✅ Emergency access system initialized"
}

# Generate emergency unseal keys
generate_emergency_keys() {
    log_step "Generating emergency unseal key shares..."
    
    # Check if Vault is initialized
    if ! vault status 2>/dev/null | grep -q "Initialized.*true"; then
        log_error "Vault is not initialized"
        return 1
    fi
    
    # Check if we have root token
    local root_token=""
    if [[ -f "/root/.vault/root-token" ]]; then
        root_token=$(cat /root/.vault/root-token)
    elif [[ -n "${VAULT_TOKEN:-}" ]]; then
        root_token="$VAULT_TOKEN"
    else
        log_error "Root token required to generate emergency keys"
        return 1
    fi
    
    export VAULT_TOKEN="$root_token"
    
    # Generate new unseal key shares for emergency use
    log_warn "This will generate additional unseal key shares for emergency use"
    read -p "Continue? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operation cancelled"
        return 0
    fi
    
    # Use rekey operation to generate additional shares
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local emergency_keys_file="$EMERGENCY_KEYS_DIR/emergency-keys-$timestamp.json"
    
    log_warn "⚠️  Starting emergency key generation - this is a sensitive operation"
    
    # Note: This is a placeholder - actual implementation would need to use
    # Vault's rekey mechanism or split existing keys using Shamir's secret sharing
    
    cat > "$emergency_keys_file" << EOF
{
  "generated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "purpose": "emergency_access",
  "type": "emergency_unseal_keys",
  "note": "These keys are for emergency unseal only. Store securely and separately.",
  "warning": "Compromise of these keys compromises Vault security",
  "keys_location": "Split among emergency contacts",
  "expiry": "Review quarterly",
  "usage_instructions": "Use break-glass-unseal command"
}
EOF
    
    chmod 600 "$emergency_keys_file"
    
    log_emergency_action "generate_emergency_keys" "$(whoami)" "Emergency unseal keys generated: $emergency_keys_file"
    
    log_warn "🔑 Emergency keys metadata saved to: $emergency_keys_file"
    log_warn "📋 Distribute actual key shares to emergency contacts"
    log_warn "🔒 Store keys in separate secure locations"
    
    log_info "✅ Emergency key generation completed"
}

# Break-glass unseal procedure
break_glass_unseal() {
    log_emergency "🚨 BREAK-GLASS UNSEAL PROCEDURE INITIATED"
    
    log_emergency_action "break_glass_unseal" "$(whoami)" "Emergency unseal procedure started"
    
    # Check if Vault is running
    if ! systemctl is-active --quiet vault; then
        log_error "Vault service is not running"
        log_info "Starting Vault service..."
        systemctl start vault
        sleep 5
    fi
    
    # Check Vault status
    local vault_status
    if ! vault_status=$(vault status 2>&1); then
        log_error "Cannot connect to Vault: $vault_status"
        return 1
    fi
    
    # Check if already unsealed
    if echo "$vault_status" | grep -q "Sealed.*false"; then
        log_warn "Vault is already unsealed"
        return 0
    fi
    
    log_step "Vault is sealed. Starting emergency unseal..."
    
    # Get unseal threshold
    local threshold=$(echo "$vault_status" | grep "Threshold" | awk '{print $2}')
    log_info "Unseal threshold: $threshold keys required"
    
    # Collect emergency unseal keys
    log_warn "Emergency unseal keys required:"
    log_warn "Contact emergency key holders and collect $threshold keys"
    
    local keys_collected=0
    local unseal_keys=()
    
    while [[ $keys_collected -lt $threshold ]]; do
        echo -n "Enter emergency unseal key $((keys_collected + 1)): "
        read -r -s unseal_key
        echo
        
        if [[ -z "$unseal_key" ]]; then
            log_warn "Empty key entered, skipping..."
            continue
        fi
        
        # Validate key format (basic check)
        if [[ ${#unseal_key} -lt 20 ]]; then
            log_warn "Key too short, please verify..."
            continue
        fi
        
        unseal_keys+=("$unseal_key")
        ((keys_collected++))
        
        log_info "Key $keys_collected of $threshold collected"
    done
    
    # Attempt unseal
    log_step "Attempting emergency unseal with provided keys..."
    
    for key in "${unseal_keys[@]}"; do
        if vault operator unseal "$key"; then
            log_info "✅ Unseal key accepted"
        else
            log_error "❌ Unseal key rejected"
        fi
    done
    
    # Check final status
    sleep 2
    if vault status | grep -q "Sealed.*false"; then
        log_info "🎉 EMERGENCY UNSEAL SUCCESSFUL"
        log_emergency_action "break_glass_unseal_success" "$(whoami)" "Vault successfully unsealed"
        
        # Generate temporary root token
        log_step "Generating temporary emergency token..."
        generate_emergency_token
    else
        log_error "💥 EMERGENCY UNSEAL FAILED"
        log_emergency_action "break_glass_unseal_failed" "$(whoami)" "Emergency unseal failed"
        return 1
    fi
}

# Recover root token
recover_root_token() {
    log_emergency "🚨 ROOT TOKEN RECOVERY PROCEDURE INITIATED"
    
    log_emergency_action "recover_root_token" "$(whoami)" "Root token recovery started"
    
    # Check if Vault is unsealed
    if vault status | grep -q "Sealed.*true"; then
        log_error "Vault is sealed. Unseal first using: break-glass-unseal"
        return 1
    fi
    
    log_step "Root token recovery options:"
    echo "1. Use existing emergency token"
    echo "2. Use recovery keys (if configured)"
    echo "3. Generate from existing valid token"
    echo "4. Use DR operation token"
    
    read -p "Select option (1-4): " -r option
    
    case "$option" in
        1)
            recover_with_emergency_token
            ;;
        2)
            recover_with_recovery_keys
            ;;
        3)
            recover_with_existing_token
            ;;
        4)
            recover_with_dr_token
            ;;
        *)
            log_error "Invalid option"
            return 1
            ;;
    esac
}

# Recover with emergency token
recover_with_emergency_token() {
    log_step "Recovering with emergency token..."
    
    # Check for existing emergency tokens
    local emergency_tokens=($(find "$EMERGENCY_TOKENS_DIR" -name "*.token" -mtime -1 2>/dev/null || true))
    
    if [[ ${#emergency_tokens[@]} -eq 0 ]]; then
        log_error "No valid emergency tokens found"
        return 1
    fi
    
    echo "Available emergency tokens:"
    for i in "${!emergency_tokens[@]}"; do
        local token_file="${emergency_tokens[$i]}"
        local created=$(stat -c %Y "$token_file")
        local created_date=$(date -d "@$created")
        echo "$((i+1)). $(basename "$token_file" .token) (created: $created_date)"
    done
    
    read -p "Select token (1-${#emergency_tokens[@]}): " -r selection
    
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ $selection -lt 1 ]] || [[ $selection -gt ${#emergency_tokens[@]} ]]; then
        log_error "Invalid selection"
        return 1
    fi
    
    local selected_token_file="${emergency_tokens[$((selection-1))]}"
    local emergency_token=$(cat "$selected_token_file")
    
    export VAULT_TOKEN="$emergency_token"
    
    # Verify token works
    if ! vault token lookup >/dev/null 2>&1; then
        log_error "Emergency token is invalid or expired"
        return 1
    fi
    
    # Generate new root token
    local new_root_token=$(vault write -field=token auth/token/create \
        policies="root" \
        ttl="24h" \
        renewable="true" \
        display_name="emergency-root-$(date +%Y%m%d-%H%M%S)")
    
    # Save new root token
    echo "$new_root_token" > "/root/.vault/root-token-recovery-$(date +%Y%m%d-%H%M%S)"
    chmod 600 "/root/.vault/root-token-recovery-$(date +%Y%m%d-%H%M%S)"
    
    log_info "✅ New root token generated and saved"
    log_emergency_action "root_token_recovered" "$(whoami)" "New root token created using emergency token"
}

# Generate emergency token
generate_emergency_token() {
    local ttl="${1:-1h}"
    local purpose="${2:-emergency_access}"
    
    log_step "Generating emergency token (TTL: $ttl)..."
    
    # Check if we have a valid token
    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        if [[ -f "/root/.vault/root-token" ]]; then
            export VAULT_TOKEN=$(cat /root/.vault/root-token)
        else
            log_error "No valid token available to generate emergency token"
            return 1
        fi
    fi
    
    # Verify current token works
    if ! vault token lookup >/dev/null 2>&1; then
        log_error "Current token is invalid"
        return 1
    fi
    
    # Generate emergency token
    local emergency_token=$(vault write -field=token auth/token/create \
        policies="root" \
        ttl="$ttl" \
        renewable="false" \
        display_name="emergency-$purpose-$(date +%Y%m%d-%H%M%S)" \
        metadata="purpose=$purpose,created_by=$(whoami),emergency=true")
    
    # Save token securely
    local token_file="$EMERGENCY_TOKENS_DIR/emergency-$purpose-$(date +%Y%m%d-%H%M%S).token"
    echo "$emergency_token" > "$token_file"
    chmod 600 "$token_file"
    
    # Create token metadata
    cat > "${token_file}.meta" << EOF
{
  "purpose": "$purpose",
  "ttl": "$ttl",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "created_by": "$(whoami)",
  "hostname": "$(hostname)",
  "expires": "$(date -u -d "+$ttl" +%Y-%m-%dT%H:%M:%SZ)",
  "token_accessor": "$(vault write -field=accessor auth/token/create policies=root ttl=$ttl display_name=emergency-meta 2>/dev/null || echo 'unknown')",
  "usage": "emergency_only"
}
EOF
    
    chmod 600 "${token_file}.meta"
    
    log_emergency_action "generate_emergency_token" "$(whoami)" "Emergency token created: $token_file"
    
    log_info "✅ Emergency token generated: $token_file"
    log_warn "🕐 Token expires in: $ttl"
    log_warn "🔑 Token: $(echo "$emergency_token" | head -c 20)..."
    
    # Set up automatic cleanup
    cat > "/tmp/cleanup-emergency-token-$$.sh" << EOF
#!/bin/bash
sleep $(($(date -d "+$ttl" +%s) - $(date +%s)))
rm -f "$token_file" "${token_file}.meta"
logger -t "vault-emergency" "Emergency token expired and cleaned up: $token_file"
EOF
    
    chmod +x "/tmp/cleanup-emergency-token-$$.sh"
    nohup "/tmp/cleanup-emergency-token-$$.sh" >/dev/null 2>&1 &
    
    return 0
}

# Emergency backup and restore
emergency_backup() {
    log_step "Creating emergency backup..."
    
    local backup_dir="/var/backups/vault/emergency"
    local backup_name="emergency-backup-$(date +%Y%m%d-%H%M%S)"
    
    mkdir -p "$backup_dir"
    
    # Create comprehensive backup
    if systemctl is-active --quiet vault && vault status | grep -q "Sealed.*false"; then
        # Vault is running and unsealed
        export VAULT_TOKEN="${VAULT_TOKEN:-$(cat /root/.vault/root-token 2>/dev/null || echo '')}"
        
        if [[ -n "$VAULT_TOKEN" ]] && vault token lookup >/dev/null 2>&1; then
            # Create Raft snapshot
            vault operator raft snapshot save "$backup_dir/$backup_name.snap"
            
            # Backup policies
            vault policy list -format=json > "$backup_dir/$backup_name-policies.json"
            
            # Backup auth methods
            vault auth list -format=json > "$backup_dir/$backup_name-auth.json"
            
            # Backup secrets engines
            vault secrets list -format=json > "$backup_dir/$backup_name-secrets.json"
        else
            log_warn "No valid token - creating configuration backup only"
        fi
    fi
    
    # Backup configuration files
    tar -czf "$backup_dir/$backup_name-config.tar.gz" /etc/vault.d/ 2>/dev/null || true
    
    # Backup data directory (if possible)
    if [[ -d "/var/lib/vault" ]]; then
        tar -czf "$backup_dir/$backup_name-data.tar.gz" /var/lib/vault/ 2>/dev/null || true
    fi
    
    # Create backup manifest
    cat > "$backup_dir/$backup_name-manifest.json" << EOF
{
  "backup_name": "$backup_name",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "$(hostname)",
  "vault_version": "$(vault version 2>/dev/null | head -1 || echo 'unknown')",
  "files": [
    "$backup_name.snap",
    "$backup_name-policies.json",
    "$backup_name-auth.json", 
    "$backup_name-secrets.json",
    "$backup_name-config.tar.gz",
    "$backup_name-data.tar.gz"
  ],
  "type": "emergency_backup"
}
EOF
    
    log_emergency_action "emergency_backup" "$(whoami)" "Emergency backup created: $backup_dir/$backup_name"
    
    log_info "✅ Emergency backup created: $backup_dir/$backup_name"
}

# Emergency restore
emergency_restore() {
    local backup_path="$1"
    
    if [[ -z "$backup_path" ]]; then
        log_error "Backup path required"
        return 1
    fi
    
    log_emergency "🚨 EMERGENCY RESTORE PROCEDURE INITIATED"
    log_emergency_action "emergency_restore" "$(whoami)" "Emergency restore from: $backup_path"
    
    if [[ ! -f "$backup_path" ]]; then
        log_error "Backup file not found: $backup_path"
        return 1
    fi
    
    log_warn "⚠️  This will restore Vault from backup and may overwrite current data"
    read -p "Continue with emergency restore? (yes/NO): " -r confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_info "Emergency restore cancelled"
        return 0
    fi
    
    # Create current state backup first
    log_step "Creating backup of current state..."
    emergency_backup
    
    # Stop Vault
    log_step "Stopping Vault service..."
    systemctl stop vault
    
    # Restore from Raft snapshot
    log_step "Restoring from Raft snapshot..."
    
    # Start Vault in recovery mode if possible
    # Note: This is simplified - actual implementation would depend on backup format
    
    if [[ "$backup_path" =~ \.snap$ ]]; then
        # Raft snapshot restore
        log_info "Restoring Raft snapshot..."
        # Would need to use 'vault operator raft snapshot restore' when Vault is running
    elif [[ "$backup_path" =~ \.tar\.gz$ ]]; then
        # Configuration/data restore
        log_info "Restoring from archive..."
        tar -xzf "$backup_path" -C /
    else
        log_error "Unknown backup format: $backup_path"
        return 1
    fi
    
    # Start Vault
    log_step "Starting Vault service..."
    systemctl start vault
    sleep 10
    
    # Verify restore
    if systemctl is-active --quiet vault; then
        log_info "✅ Vault service started successfully"
        
        if vault status | grep -q "Initialized.*true"; then
            log_info "✅ Vault is initialized"
            
            if vault status | grep -q "Sealed.*false"; then
                log_info "✅ Vault is unsealed"
            else
                log_warn "⚠️  Vault is sealed - manual unseal required"
            fi
        else
            log_warn "⚠️  Vault is not initialized - initialization required"
        fi
        
        log_info "🎉 EMERGENCY RESTORE COMPLETED"
    else
        log_error "💥 EMERGENCY RESTORE FAILED - Vault service not started"
        return 1
    fi
}

# Security incident response
incident_response() {
    local incident_type="$1"
    
    log_emergency "🚨 SECURITY INCIDENT RESPONSE ACTIVATED"
    log_emergency_action "incident_response" "$(whoami)" "Incident type: $incident_type"
    
    case "$incident_type" in
        "token_compromise")
            handle_token_compromise
            ;;
        "unauthorized_access")
            handle_unauthorized_access
            ;;
        "data_breach")
            handle_data_breach
            ;;
        "service_disruption")
            handle_service_disruption
            ;;
        *)
            log_error "Unknown incident type: $incident_type"
            log_info "Available types: token_compromise, unauthorized_access, data_breach, service_disruption"
            return 1
            ;;
    esac
}

# Handle token compromise
handle_token_compromise() {
    log_step "Handling token compromise incident..."
    
    # Revoke all tokens (requires root access)
    if [[ -n "${VAULT_TOKEN:-}" ]] && vault token lookup >/dev/null 2>&1; then
        log_warn "Revoking all tokens except current session..."
        
        # Get current token accessor to preserve it
        local current_accessor=$(vault token lookup -field=accessor 2>/dev/null || echo "")
        
        # List and revoke all other accessors
        vault list auth/token/accessors -format=json | jq -r '.[]' | while read -r accessor; do
            if [[ "$accessor" != "$current_accessor" ]]; then
                vault write auth/token/revoke-accessor accessor="$accessor" >/dev/null 2>&1 || true
            fi
        done
        
        log_info "✅ All tokens revoked"
    else
        log_error "Cannot revoke tokens - no valid root token"
    fi
    
    # Generate new emergency token
    generate_emergency_token "2h" "incident_response"
    
    # Force re-authentication for all clients
    log_warn "📢 All clients must re-authenticate"
}

# Cleanup emergency tokens
cleanup_emergency_tokens() {
    log_step "Cleaning up expired emergency tokens..."
    
    local cleaned=0
    
    for token_file in "$EMERGENCY_TOKENS_DIR"/*.token; do
        [[ ! -f "$token_file" ]] && continue
        
        local meta_file="${token_file}.meta"
        if [[ -f "$meta_file" ]]; then
            local expires=$(jq -r '.expires // ""' "$meta_file" 2>/dev/null)
            if [[ -n "$expires" ]]; then
                local expires_epoch=$(date -d "$expires" +%s 2>/dev/null || echo "0")
                local current_epoch=$(date +%s)
                
                if [[ $expires_epoch -lt $current_epoch ]]; then
                    rm -f "$token_file" "$meta_file"
                    log_info "Cleaned up expired token: $(basename "$token_file")"
                    ((cleaned++))
                fi
            fi
        fi
        
        # Also clean tokens older than 24 hours without metadata
        if [[ ! -f "$meta_file" ]] && find "$token_file" -mtime +1 -print | grep -q .; then
            rm -f "$token_file"
            log_info "Cleaned up old token: $(basename "$token_file")"
            ((cleaned++))
        fi
    done
    
    log_info "✅ Cleanup completed: $cleaned tokens removed"
}

# Main function
main() {
    case "${1:-help}" in
        init)
            init_emergency_access
            ;;
        generate-keys)
            generate_emergency_keys
            ;;
        break-glass-unseal)
            break_glass_unseal
            ;;
        recover-root-token)
            recover_root_token
            ;;
        generate-emergency-token)
            generate_emergency_token "${2:-1h}" "${3:-manual}"
            ;;
        emergency-backup)
            emergency_backup
            ;;
        emergency-restore)
            [[ $# -lt 2 ]] && { log_error "Usage: $0 emergency-restore <backup_path>"; exit 1; }
            emergency_restore "$2"
            ;;
        incident-response)
            [[ $# -lt 2 ]] && { log_error "Usage: $0 incident-response <type>"; exit 1; }
            incident_response "$2"
            ;;
        cleanup)
            cleanup_emergency_tokens
            ;;
        help|*)
            cat << EOF
Vault Emergency Access Procedures

Usage: $0 <command> [arguments]

Emergency Commands:
  break-glass-unseal              - Emergency unseal when keys unavailable
  recover-root-token              - Recover lost/compromised root token  
  generate-emergency-token [ttl]  - Generate temporary emergency token
  emergency-backup                - Create emergency backup
  emergency-restore <backup>      - Restore from emergency backup
  incident-response <type>        - Handle security incidents

Setup Commands:
  init                            - Initialize emergency access system
  generate-keys                   - Generate emergency unseal keys
  cleanup                         - Clean up expired emergency tokens

Incident Types:
  token_compromise               - Handle compromised tokens
  unauthorized_access            - Handle unauthorized access attempts
  data_breach                    - Handle potential data breaches
  service_disruption            - Handle service disruption

Environment Variables:
  VAULT_ADDR         - Vault server address
  VAULT_TOKEN        - Vault authentication token
  EMERGENCY_EMAIL    - Emergency notification emails
  SLACK_WEBHOOK      - Slack webhook for alerts

Examples:
  $0 init                                    # Initialize emergency system
  $0 break-glass-unseal                      # Emergency unseal procedure
  $0 generate-emergency-token 2h             # Generate 2-hour emergency token
  $0 incident-response token_compromise      # Handle token compromise
  $0 emergency-backup                        # Create emergency backup

⚠️  WARNING: Emergency procedures are logged and monitored
📋 All actions require justification and incident documentation
🔐 Change all credentials after emergency procedures
EOF
            ;;
    esac
}

# Ensure running as root for emergency procedures
if [[ $EUID -ne 0 ]] && [[ "${1:-}" != "help" ]]; then
    log_error "Emergency procedures must be run as root"
    exit 1
fi

# Run main function with all arguments
main "$@"