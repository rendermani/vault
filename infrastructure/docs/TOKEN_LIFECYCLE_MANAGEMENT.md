# Token Lifecycle Management for Nomad-Vault Integration

## Overview

This document provides comprehensive guidance on managing Vault token lifecycles in the Nomad-Vault integration, covering token creation, renewal, rotation, and revocation strategies for secure, automated operations.

## Token Types and Use Cases

### 1. Bootstrap Tokens (Phase 1)
- **Purpose**: Initial setup and configuration
- **Lifespan**: Short-lived (15 minutes to 72 hours)
- **Security**: High-privilege, must be revoked after use
- **Example**: Root tokens, initial Nomad integration tokens

### 2. Service Tokens (Phase 2)
- **Purpose**: Ongoing service operations
- **Lifespan**: Medium-lived with automatic renewal (1-24 hours)
- **Security**: Limited privileges, renewable
- **Example**: Nomad server tokens, AppRole-generated tokens

### 3. Workload Tokens (Phase 2)
- **Purpose**: Individual application access
- **Lifespan**: Short-lived with automatic renewal (30 minutes to 2 hours)
- **Security**: Application-specific policies, auto-revoked on job completion
- **Example**: Database credentials, API keys

---

## Token Creation Strategies

### Environment-Based Token Configuration

```bash
#!/bin/bash
# Environment-specific token creation

create_environment_token() {
    local environment="$1"
    local service_name="$2"
    local policy_name="$3"
    
    case "$environment" in
        "develop")
            # Development: Longer TTLs, more permissive
            vault write auth/token/create \
                policies="$policy_name" \
                ttl="4h" \
                renewable=true \
                display_name="dev-${service_name}" \
                metadata=environment="develop" \
                metadata=service="$service_name"
            ;;
        "staging")
            # Staging: Moderate TTLs, limited permissions
            vault write auth/token/create \
                policies="$policy_name" \
                ttl="2h" \
                renewable=true \
                display_name="staging-${service_name}" \
                metadata=environment="staging" \
                metadata=service="$service_name"
            ;;
        "production")
            # Production: Short TTLs, strict permissions
            vault write auth/token/create \
                policies="$policy_name" \
                ttl="1h" \
                renewable=true \
                explicit_max_ttl="24h" \
                display_name="prod-${service_name}" \
                metadata=environment="production" \
                metadata=service="$service_name"
            ;;
    esac
}
```

### Nomad Server Token Creation

```bash
#!/bin/bash
# Create tokens specifically for Nomad servers

create_nomad_server_token() {
    local environment="$1"
    local server_id="$2"
    
    log_info "Creating Nomad server token for $server_id in $environment"
    
    # Determine TTL based on environment
    local ttl max_ttl
    case "$environment" in
        "develop")
            ttl="8h"
            max_ttl="24h"
            ;;
        "staging")
            ttl="4h"
            max_ttl="12h"
            ;;
        "production")
            ttl="1h"
            max_ttl="6h"
            ;;
    esac
    
    # Create token using nomad-cluster role
    local token_response
    token_response=$(vault write -format=json auth/token/create/nomad-cluster \
        ttl="$ttl" \
        explicit_max_ttl="$max_ttl" \
        display_name="nomad-server-${server_id}" \
        metadata=environment="$environment" \
        metadata=server_id="$server_id" \
        metadata=created_by="bootstrap-script" \
        metadata=created_at="$(date -Iseconds)")
    
    local token
    token=$(echo "$token_response" | jq -r '.auth.client_token')
    
    if [[ -n "$token" && "$token" != "null" ]]; then
        # Store token securely
        echo "$token" | sudo tee "/etc/nomad.d/vault-tokens/server-${server_id}" >/dev/null
        sudo chmod 600 "/etc/nomad.d/vault-tokens/server-${server_id}"
        sudo chown nomad:nomad "/etc/nomad.d/vault-tokens/server-${server_id}"
        
        log_success "Nomad server token created and stored"
        log_info "Token TTL: $ttl, Max TTL: $max_ttl"
        
        return 0
    else
        log_error "Failed to create Nomad server token"
        return 1
    fi
}
```

---

## Token Renewal Mechanisms

### Automatic Renewal Service

```bash
#!/bin/bash
# Automatic token renewal service for Nomad-Vault integration

TOKEN_RENEWAL_SERVICE="/etc/systemd/system/vault-token-renewal.service"
TOKEN_RENEWAL_SCRIPT="/usr/local/bin/vault-token-renewal.sh"

install_token_renewal_service() {
    log_info "Installing token renewal service..."
    
    # Create renewal script
    cat > "$TOKEN_RENEWAL_SCRIPT" <<'EOF'
#!/bin/bash
# Vault Token Renewal Service

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/vault-token-renewal.log"
METRICS_FILE="/var/run/vault-token-renewal-metrics"

# Logging
log() {
    echo "$(date -Iseconds) $1" | tee -a "$LOG_FILE"
}

# Metrics
update_metric() {
    local metric="$1"
    local value="$2"
    echo "${metric}=${value}" >> "$METRICS_FILE.tmp"
    mv "$METRICS_FILE.tmp" "$METRICS_FILE"
}

# Get token info
get_token_info() {
    local token="$1"
    VAULT_TOKEN="$token" vault token lookup-self -format=json 2>/dev/null || echo "{}"
}

# Renew token
renew_token() {
    local token="$1"
    local service_name="$2"
    
    log "Attempting to renew token for service: $service_name"
    
    # Get current token info
    local token_info
    token_info=$(get_token_info "$token")
    
    local ttl renewable
    ttl=$(echo "$token_info" | jq -r '.data.ttl // 0')
    renewable=$(echo "$token_info" | jq -r '.data.renewable // false')
    
    if [[ "$renewable" == "false" ]]; then
        log "ERROR: Token for $service_name is not renewable"
        return 1
    fi
    
    # Check if renewal is needed (renew when TTL < 30% of original)
    local original_ttl
    original_ttl=$(echo "$token_info" | jq -r '.data.creation_ttl // 3600')
    local renewal_threshold=$((original_ttl * 30 / 100))
    
    if [[ $ttl -lt $renewal_threshold ]]; then
        log "Renewing token for $service_name (TTL: ${ttl}s < threshold: ${renewal_threshold}s)"
        
        # Attempt renewal
        local renewal_result
        renewal_result=$(VAULT_TOKEN="$token" vault token renew -format=json 2>/dev/null || echo "{}")
        
        local new_ttl
        new_ttl=$(echo "$renewal_result" | jq -r '.auth.lease_duration // 0')
        
        if [[ $new_ttl -gt $ttl ]]; then
            log "Successfully renewed token for $service_name: TTL ${ttl}s -> ${new_ttl}s"
            update_metric "vault_token_renewals_total" $(($(cat "$METRICS_FILE" 2>/dev/null | grep renewals_total | cut -d= -f2 || echo 0) + 1))
            return 0
        else
            log "ERROR: Token renewal failed for $service_name"
            update_metric "vault_token_renewal_failures_total" $(($(cat "$METRICS_FILE" 2>/dev/null | grep renewal_failures | cut -d= -f2 || echo 0) + 1))
            return 1
        fi
    else
        log "Token for $service_name does not need renewal yet (TTL: ${ttl}s)"
        return 0
    fi
}

# Main renewal loop
main() {
    log "Starting token renewal service"
    
    # Create metrics file
    touch "$METRICS_FILE"
    
    while true; do
        log "Running token renewal cycle"
        
        local renewal_failures=0
        
        # Renew Nomad server tokens
        for token_file in /etc/nomad.d/vault-tokens/server-*; do
            if [[ -f "$token_file" ]]; then
                local server_id
                server_id=$(basename "$token_file" | sed 's/server-//')
                
                local token
                token=$(cat "$token_file" 2>/dev/null || echo "")
                
                if [[ -n "$token" ]]; then
                    if ! renew_token "$token" "nomad-server-$server_id"; then
                        ((renewal_failures++))
                    fi
                fi
            fi
        done
        
        # Renew AppRole tokens (if stored)
        if [[ -d "/etc/nomad.d/vault-tokens/approle" ]]; then
            for approle_token in /etc/nomad.d/vault-tokens/approle/*; do
                if [[ -f "$approle_token" ]]; then
                    local role_name
                    role_name=$(basename "$approle_token")
                    
                    local token
                    token=$(cat "$approle_token" 2>/dev/null || echo "")
                    
                    if [[ -n "$token" ]]; then
                        if ! renew_token "$token" "approle-$role_name"; then
                            ((renewal_failures++))
                        fi
                    fi
                fi
            done
        fi
        
        # Update failure metrics
        update_metric "vault_token_renewal_failures_last_cycle" "$renewal_failures"
        
        # Sleep for 5 minutes between cycles
        sleep 300
    done
}

# Handle signals
trap 'log "Token renewal service stopping"; exit 0' SIGTERM SIGINT

# Start main loop
main
EOF
    
    chmod +x "$TOKEN_RENEWAL_SCRIPT"
    
    # Create systemd service
    cat > "$TOKEN_RENEWAL_SERVICE" <<EOF
[Unit]
Description=Vault Token Renewal Service
After=network.target vault.service nomad.service
Wants=vault.service nomad.service

[Service]
Type=simple
User=vault
Group=vault
ExecStart=$TOKEN_RENEWAL_SCRIPT
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/var/log /var/run /etc/nomad.d/vault-tokens
ProtectHome=true
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictSUIDSGID=true

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable and start service
    systemctl daemon-reload
    systemctl enable vault-token-renewal.service
    systemctl start vault-token-renewal.service
    
    log_success "Token renewal service installed and started"
}
```

### Smart Renewal with Backoff

```bash
#!/bin/bash
# Smart token renewal with exponential backoff

renew_token_with_backoff() {
    local token="$1"
    local service_name="$2"
    local max_retries="${3:-5}"
    
    local retry_count=0
    local backoff_seconds=1
    
    while [[ $retry_count -lt $max_retries ]]; do
        log_info "Attempting token renewal for $service_name (attempt $((retry_count + 1))/$max_retries)"
        
        # Get current token status
        local token_info
        token_info=$(VAULT_TOKEN="$token" vault token lookup-self -format=json 2>/dev/null || echo "{}")
        
        if [[ "$token_info" == "{}" ]]; then
            log_error "Token for $service_name is invalid or expired"
            return 1
        fi
        
        local ttl renewable
        ttl=$(echo "$token_info" | jq -r '.data.ttl // 0')
        renewable=$(echo "$token_info" | jq -r '.data.renewable // false')
        
        if [[ "$renewable" != "true" ]]; then
            log_error "Token for $service_name is not renewable"
            return 1
        fi
        
        # Attempt renewal
        local renewal_response
        renewal_response=$(VAULT_TOKEN="$token" vault token renew -format=json 2>/dev/null || echo "{}")
        
        local new_ttl
        new_ttl=$(echo "$renewal_response" | jq -r '.auth.lease_duration // 0')
        
        if [[ $new_ttl -gt 0 ]]; then
            log_success "Token renewed for $service_name: TTL ${ttl}s -> ${new_ttl}s"
            
            # Update metrics
            echo "vault_token_last_renewal_$(echo "$service_name" | tr '-' '_')=$(date +%s)" >> /var/run/vault-metrics
            
            return 0
        else
            log_warning "Token renewal failed for $service_name (attempt $((retry_count + 1)))"
            
            ((retry_count++))
            
            if [[ $retry_count -lt $max_retries ]]; then
                log_info "Retrying in ${backoff_seconds}s..."
                sleep $backoff_seconds
                backoff_seconds=$((backoff_seconds * 2))  # Exponential backoff
            fi
        fi
    done
    
    log_error "Token renewal failed for $service_name after $max_retries attempts"
    
    # Alert on failure
    alert_operations_team "Token renewal failed for $service_name after $max_retries attempts"
    
    return 1
}
```

---

## Token Rotation Strategies

### Proactive Token Rotation

```bash
#!/bin/bash
# Proactive token rotation for enhanced security

rotate_nomad_server_tokens() {
    local environment="$1"
    
    log_info "Starting proactive token rotation for Nomad servers in $environment"
    
    # Get list of current server tokens
    local server_tokens
    server_tokens=$(find /etc/nomad.d/vault-tokens -name "server-*" -type f)
    
    while IFS= read -r token_file; do
        if [[ -n "$token_file" && -f "$token_file" ]]; then
            local server_id
            server_id=$(basename "$token_file" | sed 's/server-//')
            
            log_info "Rotating token for server: $server_id"
            
            # Get current token
            local old_token
            old_token=$(cat "$token_file" 2>/dev/null || echo "")
            
            if [[ -z "$old_token" ]]; then
                log_warning "No token found for server $server_id"
                continue
            fi
            
            # Create new token
            local new_token
            new_token=$(create_nomad_server_token "$environment" "$server_id")
            
            if [[ -n "$new_token" ]]; then
                # Update Nomad configuration with new token
                update_nomad_vault_token "$server_id" "$new_token"
                
                # Give Nomad time to use the new token
                sleep 30
                
                # Verify the new token works
                if verify_nomad_vault_integration "$server_id"; then
                    # Revoke old token
                    vault token revoke "$old_token" >/dev/null 2>&1 || true
                    
                    log_success "Token rotation completed for server $server_id"
                else
                    log_error "Token rotation verification failed for server $server_id"
                    
                    # Rollback: restore old token
                    echo "$old_token" | sudo tee "$token_file" >/dev/null
                    update_nomad_vault_token "$server_id" "$old_token"
                    
                    # Revoke the failed new token
                    vault token revoke "$new_token" >/dev/null 2>&1 || true
                fi
            else
                log_error "Failed to create new token for server $server_id"
            fi
        fi
    done <<< "$server_tokens"
    
    log_success "Token rotation cycle completed"
}

# Update Nomad configuration with new token
update_nomad_vault_token() {
    local server_id="$1"
    local new_token="$2"
    
    # Update configuration file
    local config_file="/etc/nomad.d/vault-integration.hcl"
    
    if [[ -f "$config_file" ]]; then
        # Create backup
        cp "$config_file" "${config_file}.backup-$(date +%s)"
        
        # Update token in configuration
        sed -i "s/token = \".*\"/token = \"$new_token\"/" "$config_file"
        
        # Reload Nomad configuration
        systemctl reload nomad
        
        log_info "Updated Nomad configuration with new token for server $server_id"
    else
        log_warning "Nomad configuration file not found: $config_file"
    fi
}

# Verify Nomad-Vault integration is working
verify_nomad_vault_integration() {
    local server_id="$1"
    local max_attempts=6
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if nomad server members | grep -q "$server_id"; then
            if nomad job status vault-test >/dev/null 2>&1 || nomad node status >/dev/null 2>&1; then
                log_debug "Nomad-Vault integration verified for server $server_id"
                return 0
            fi
        fi
        
        ((attempt++))
        sleep 10
    done
    
    log_error "Nomad-Vault integration verification failed for server $server_id"
    return 1
}
```

### Scheduled Token Rotation

```bash
#!/bin/bash
# Scheduled token rotation with cron integration

setup_token_rotation_schedule() {
    log_info "Setting up scheduled token rotation..."
    
    # Create rotation script
    cat > /usr/local/bin/vault-token-rotation.sh <<'EOF'
#!/bin/bash
# Scheduled Vault token rotation

set -euo pipefail

ENVIRONMENT="${ENVIRONMENT:-production}"
LOG_FILE="/var/log/vault-token-rotation.log"

# Logging
log() {
    echo "$(date -Iseconds) $1" | tee -a "$LOG_FILE"
}

# Source environment configuration
if [[ -f "/etc/vault-token-rotation/config" ]]; then
    source /etc/vault-token-rotation/config
fi

# Rotation logic
main() {
    log "Starting scheduled token rotation for environment: $ENVIRONMENT"
    
    # Check if rotation is needed
    if needs_rotation; then
        log "Token rotation is needed, proceeding..."
        
        if rotate_all_tokens "$ENVIRONMENT"; then
            log "Token rotation completed successfully"
            
            # Update rotation timestamp
            echo "$(date +%s)" > /var/run/vault-last-rotation
            
            # Alert success
            alert_operations_team "Token rotation completed successfully in $ENVIRONMENT"
        else
            log "Token rotation failed"
            alert_security_team "Token rotation failed in $ENVIRONMENT"
            exit 1
        fi
    else
        log "Token rotation not needed at this time"
    fi
}

# Check if rotation is needed
needs_rotation() {
    local last_rotation_file="/var/run/vault-last-rotation"
    local rotation_interval_hours="${ROTATION_INTERVAL_HOURS:-168}"  # Weekly by default
    
    if [[ ! -f "$last_rotation_file" ]]; then
        log "No previous rotation timestamp found, rotation needed"
        return 0
    fi
    
    local last_rotation current_time hours_since_rotation
    last_rotation=$(cat "$last_rotation_file" 2>/dev/null || echo "0")
    current_time=$(date +%s)
    hours_since_rotation=$(( (current_time - last_rotation) / 3600 ))
    
    if [[ $hours_since_rotation -ge $rotation_interval_hours ]]; then
        log "Rotation needed: ${hours_since_rotation}h since last rotation (threshold: ${rotation_interval_hours}h)"
        return 0
    else
        log "Rotation not needed: ${hours_since_rotation}h since last rotation (threshold: ${rotation_interval_hours}h)"
        return 1
    fi
}

# Alert functions
alert_operations_team() {
    local message="$1"
    logger -t vault-rotation "OPS: $message"
    # Add webhook/email notification here
}

alert_security_team() {
    local message="$1"
    logger -t vault-rotation "SECURITY: $message"
    # Add security team notification here
}

# Run main function
main "$@"
EOF
    
    chmod +x /usr/local/bin/vault-token-rotation.sh
    
    # Create configuration
    mkdir -p /etc/vault-token-rotation
    cat > /etc/vault-token-rotation/config <<EOF
# Token rotation configuration
ENVIRONMENT="$ENVIRONMENT"
ROTATION_INTERVAL_HOURS=168  # Weekly rotation
VAULT_ADDR="$VAULT_ADDR"
NOMAD_ADDR="$NOMAD_ADDR"
EOF
    
    # Add to cron (weekly rotation)
    cat > /etc/cron.d/vault-token-rotation <<EOF
# Vault Token Rotation Schedule
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Weekly token rotation (Sunday at 2 AM)
0 2 * * 0 vault /usr/local/bin/vault-token-rotation.sh
EOF
    
    log_success "Token rotation schedule configured"
}
```

---

## Token Revocation and Cleanup

### Emergency Token Revocation

```bash
#!/bin/bash
# Emergency token revocation procedures

emergency_revoke_all_tokens() {
    local reason="$1"
    local exclude_tokens="${2:-}"  # Comma-separated list of tokens to exclude
    
    log_warning "EMERGENCY: Revoking all tokens - Reason: $reason"
    
    # Create exclusion array
    IFS=',' read -ra EXCLUDE_ARRAY <<< "$exclude_tokens"
    
    # Get all active tokens
    local all_tokens
    all_tokens=$(vault auth -method=token -help 2>&1 | grep "List active tokens" || echo "")
    
    # Alternative: revoke by prefix
    log_info "Revoking all auth/token/ leases..."
    
    # Revoke all token-based leases
    if vault write sys/leases/revoke-prefix prefix=auth/token/; then
        log_success "Successfully revoked all token-based leases"
    else
        log_error "Failed to revoke token-based leases"
    fi
    
    # Revoke tokens stored in files
    log_info "Revoking tokens from storage locations..."
    
    # Nomad server tokens
    for token_file in /etc/nomad.d/vault-tokens/server-*; do
        if [[ -f "$token_file" ]]; then
            local token
            token=$(cat "$token_file" 2>/dev/null || echo "")
            
            if [[ -n "$token" ]]; then
                local exclude=false
                for exclude_token in "${EXCLUDE_ARRAY[@]}"; do
                    if [[ "$token" == "$exclude_token" ]]; then
                        exclude=true
                        break
                    fi
                done
                
                if ! $exclude; then
                    vault token revoke "$token" >/dev/null 2>&1 || true
                    log_info "Revoked token from $(basename "$token_file")"
                    
                    # Clear the file
                    > "$token_file"
                fi
            fi
        fi
    done
    
    # AppRole tokens
    if [[ -d "/etc/nomad.d/vault-tokens/approle" ]]; then
        for approle_token in /etc/nomad.d/vault-tokens/approle/*; do
            if [[ -f "$approle_token" ]]; then
                local token
                token=$(cat "$approle_token" 2>/dev/null || echo "")
                
                if [[ -n "$token" ]]; then
                    vault token revoke "$token" >/dev/null 2>&1 || true
                    log_info "Revoked AppRole token from $(basename "$approle_token")"
                    
                    # Clear the file
                    > "$approle_token"
                fi
            fi
        done
    fi
    
    # Alert security team
    alert_security_team "Emergency token revocation completed: $reason"
    
    log_warning "Emergency token revocation completed - All services will need new tokens"
}

# Cleanup expired tokens
cleanup_expired_tokens() {
    log_info "Cleaning up expired tokens..."
    
    local cleanup_count=0
    
    # Check token files for expired tokens
    for token_file in /etc/nomad.d/vault-tokens/**/*; do
        if [[ -f "$token_file" ]]; then
            local token
            token=$(cat "$token_file" 2>/dev/null || echo "")
            
            if [[ -n "$token" ]]; then
                # Check if token is still valid
                if ! VAULT_TOKEN="$token" vault token lookup-self >/dev/null 2>&1; then
                    log_info "Found expired token in $token_file"
                    
                    # Clear expired token
                    > "$token_file"
                    ((cleanup_count++))
                fi
            fi
        fi
    done
    
    log_success "Cleaned up $cleanup_count expired tokens"
}

# Revoke tokens by metadata
revoke_tokens_by_metadata() {
    local metadata_key="$1"
    local metadata_value="$2"
    
    log_info "Revoking tokens with metadata $metadata_key=$metadata_value"
    
    # This would require API calls to list tokens and filter by metadata
    # Implementation depends on Vault version and available APIs
    
    log_warning "Metadata-based token revocation requires manual implementation"
    log_warning "Consider using vault auth list-accessors and filtering approach"
}
```

---

## Monitoring and Alerting

### Token Health Monitoring

```bash
#!/bin/bash
# Comprehensive token health monitoring

monitor_token_health() {
    log_info "Starting token health monitoring..."
    
    local unhealthy_tokens=0
    local expiring_tokens=0
    local total_tokens=0
    
    # Check Nomad server tokens
    for token_file in /etc/nomad.d/vault-tokens/server-*; do
        if [[ -f "$token_file" ]]; then
            local server_id
            server_id=$(basename "$token_file" | sed 's/server-//')
            
            local token
            token=$(cat "$token_file" 2>/dev/null || echo "")
            
            if [[ -n "$token" ]]; then
                ((total_tokens++))
                
                if check_token_health "$token" "$server_id"; then
                    local ttl
                    ttl=$(get_token_ttl "$token")
                    
                    # Alert if token expires soon (< 10% of original TTL)
                    if [[ $ttl -lt 360 ]]; then  # Less than 6 minutes
                        ((expiring_tokens++))
                        log_warning "Token for server $server_id expires soon: ${ttl}s"
                        
                        # Auto-renew if possible
                        if renew_token_with_backoff "$token" "nomad-server-$server_id"; then
                            log_success "Auto-renewed token for server $server_id"
                        fi
                    fi
                else
                    ((unhealthy_tokens++))
                fi
            else
                log_error "No token found for server $server_id"
                ((unhealthy_tokens++))
            fi
        fi
    done
    
    # Update metrics
    update_token_metrics "$total_tokens" "$unhealthy_tokens" "$expiring_tokens"
    
    # Generate alerts if needed
    if [[ $unhealthy_tokens -gt 0 ]]; then
        alert_operations_team "Found $unhealthy_tokens unhealthy tokens out of $total_tokens"
    fi
    
    if [[ $expiring_tokens -gt 0 ]]; then
        alert_operations_team "Found $expiring_tokens tokens expiring soon out of $total_tokens"
    fi
    
    log_success "Token health monitoring completed: $total_tokens total, $unhealthy_tokens unhealthy, $expiring_tokens expiring"
}

check_token_health() {
    local token="$1"
    local service_name="$2"
    
    # Check if token is valid and accessible
    local token_info
    token_info=$(VAULT_TOKEN="$token" vault token lookup-self -format=json 2>/dev/null || echo "{}")
    
    if [[ "$token_info" == "{}" ]]; then
        log_error "Token for $service_name is invalid or inaccessible"
        return 1
    fi
    
    # Check if token has required policies
    local policies
    policies=$(echo "$token_info" | jq -r '.data.policies[]' 2>/dev/null | tr '\n' ' ')
    
    if [[ -z "$policies" ]]; then
        log_error "Token for $service_name has no policies"
        return 1
    fi
    
    # Check TTL
    local ttl
    ttl=$(echo "$token_info" | jq -r '.data.ttl // 0')
    
    if [[ $ttl -eq 0 ]]; then
        log_error "Token for $service_name has no TTL (may be expired)"
        return 1
    fi
    
    log_debug "Token for $service_name is healthy: TTL=${ttl}s, policies=[$policies]"
    return 0
}

get_token_ttl() {
    local token="$1"
    VAULT_TOKEN="$token" vault token lookup-self -format=json 2>/dev/null | jq -r '.data.ttl // 0'
}

update_token_metrics() {
    local total="$1"
    local unhealthy="$2"
    local expiring="$3"
    
    local metrics_file="/var/run/vault-token-metrics"
    
    cat > "$metrics_file" <<EOF
# Vault Token Health Metrics
vault_tokens_total=$total
vault_tokens_unhealthy=$unhealthy
vault_tokens_expiring_soon=$expiring
vault_token_health_last_check=$(date +%s)
EOF
    
    # Also expose as Prometheus metrics if needed
    if command -v curl >/dev/null 2>&1 && [[ -n "${PROMETHEUS_PUSHGATEWAY:-}" ]]; then
        cat <<EOF | curl -X POST "${PROMETHEUS_PUSHGATEWAY}/metrics/job/vault-token-health" --data-binary @-
vault_tokens_total $total
vault_tokens_unhealthy $unhealthy
vault_tokens_expiring_soon $expiring
EOF
    fi
}
```

### Automated Recovery Procedures

```bash
#!/bin/bash
# Automated recovery procedures for token issues

auto_recover_tokens() {
    local recovery_mode="${1:-conservative}"  # conservative|aggressive
    
    log_info "Starting automated token recovery in $recovery_mode mode"
    
    case "$recovery_mode" in
        "conservative")
            # Only recover obviously failed tokens
            recover_dead_tokens
            ;;
        "aggressive") 
            # Proactively recreate problematic tokens
            recover_dead_tokens
            recover_expiring_tokens
            recover_problematic_tokens
            ;;
        *)
            log_error "Unknown recovery mode: $recovery_mode"
            return 1
            ;;
    esac
}

recover_dead_tokens() {
    log_info "Recovering dead/invalid tokens..."
    
    for token_file in /etc/nomad.d/vault-tokens/server-*; do
        if [[ -f "$token_file" ]]; then
            local server_id
            server_id=$(basename "$token_file" | sed 's/server-//')
            
            local token
            token=$(cat "$token_file" 2>/dev/null || echo "")
            
            if [[ -n "$token" ]]; then
                # Check if token is dead
                if ! VAULT_TOKEN="$token" vault token lookup-self >/dev/null 2>&1; then
                    log_warning "Found dead token for server $server_id, creating replacement"
                    
                    # Create new token
                    local new_token
                    new_token=$(create_nomad_server_token "$ENVIRONMENT" "$server_id")
                    
                    if [[ -n "$new_token" ]]; then
                        # Update configuration
                        update_nomad_vault_token "$server_id" "$new_token"
                        
                        log_success "Recovered dead token for server $server_id"
                    else
                        log_error "Failed to recover dead token for server $server_id"
                    fi
                fi
            else
                log_warning "Empty token file for server $server_id, creating new token"
                
                # Create new token
                local new_token
                new_token=$(create_nomad_server_token "$ENVIRONMENT" "$server_id")
                
                if [[ -n "$new_token" ]]; then
                    update_nomad_vault_token "$server_id" "$new_token"
                    log_success "Created token for server $server_id (was empty)"
                fi
            fi
        fi
    done
}

recover_expiring_tokens() {
    log_info "Proactively renewing expiring tokens..."
    
    for token_file in /etc/nomad.d/vault-tokens/server-*; do
        if [[ -f "$token_file" ]]; then
            local server_id
            server_id=$(basename "$token_file" | sed 's/server-//')
            
            local token
            token=$(cat "$token_file" 2>/dev/null || echo "")
            
            if [[ -n "$token" ]]; then
                local ttl
                ttl=$(get_token_ttl "$token")
                
                # Renew if less than 20% of original TTL remains
                if [[ $ttl -lt 720 ]]; then  # Less than 12 minutes
                    log_info "Proactively renewing token for server $server_id (TTL: ${ttl}s)"
                    
                    if renew_token_with_backoff "$token" "nomad-server-$server_id"; then
                        log_success "Proactively renewed token for server $server_id"
                    else
                        log_warning "Failed to renew token for server $server_id, may need replacement"
                    fi
                fi
            fi
        fi
    done
}
```

## Security Best Practices

### Token Security Hardening

1. **Minimal TTLs**: Use the shortest reasonable TTL for each token type
2. **Regular Rotation**: Implement automated token rotation schedules
3. **Principle of Least Privilege**: Grant only necessary permissions
4. **Audit Logging**: Monitor all token operations
5. **Secure Storage**: Protect token storage with appropriate file permissions
6. **Emergency Procedures**: Have tested procedures for token compromise scenarios

### Production Recommendations

- **Environment Separation**: Different token management strategies per environment
- **Monitoring Integration**: Integrate with existing monitoring and alerting systems
- **Backup Procedures**: Maintain secure backups of critical tokens
- **Documentation**: Keep detailed documentation of token purposes and lifecycles
- **Testing**: Regular testing of renewal and rotation procedures

This comprehensive token lifecycle management ensures secure, automated operation of the Nomad-Vault integration with appropriate monitoring, recovery, and security measures.