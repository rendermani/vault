#!/bin/bash

# Consul Security Automation Script
# Handles ACL management, token rotation, and security validation
# Usage: ./consul-security-automation.sh [command] [environment]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONSUL_CONFIG_DIR="$PROJECT_ROOT/infrastructure/config"
CONSUL_DATA_DIR="/opt/consul"
LOG_FILE="/var/log/consul-security.log"

# Environment variables
CONSUL_HTTP_ADDR="${CONSUL_HTTP_ADDR:-http://127.0.0.1:8500}"
CONSUL_CACERT="${CONSUL_CACERT:-}"
CONSUL_CLIENT_CERT="${CONSUL_CLIENT_CERT:-}"
CONSUL_CLIENT_KEY="${CONSUL_CLIENT_KEY:-}"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Error handling
error() {
    log "ERROR: $*"
    exit 1
}

# Check if consul command is available
check_consul_binary() {
    if ! command -v consul &> /dev/null; then
        error "Consul binary not found. Please install Consul."
    fi
}

# Generate secure gossip encryption key
generate_gossip_key() {
    log "Generating new gossip encryption key..."
    consul keygen
}

# Bootstrap ACL system
bootstrap_acl() {
    local env="$1"
    log "Bootstrapping ACL system for environment: $env"
    
    local bootstrap_token
    if ! bootstrap_token=$(consul acl bootstrap -format=json 2>/dev/null); then
        log "ACL system may already be bootstrapped or Consul not running"
        return 1
    fi
    
    local token_id
    token_id=$(echo "$bootstrap_token" | jq -r '.SecretID')
    
    # Save bootstrap token securely
    echo "CONSUL_BOOTSTRAP_TOKEN=$token_id" >> "/tmp/consul-bootstrap-$env.env"
    chmod 600 "/tmp/consul-bootstrap-$env.env"
    
    log "Bootstrap token generated and saved to /tmp/consul-bootstrap-$env.env"
    log "WARNING: Store this token securely and delete the temp file!"
    
    export CONSUL_HTTP_TOKEN="$token_id"
}

# Create service-specific tokens
create_service_tokens() {
    local env="$1"
    log "Creating service-specific tokens for environment: $env"
    
    # Vault service token
    local vault_policy="vault-policy-$env"
    consul acl policy create \
        -name "$vault_policy" \
        -description "Policy for Vault service in $env" \
        -rules 'node_prefix "" { policy = "write" } service_prefix "vault" { policy = "write" } key_prefix "vault/" { policy = "write" }'
    
    local vault_token
    vault_token=$(consul acl token create \
        -description "Vault service token for $env" \
        -policy-name "$vault_policy" \
        -format=json | jq -r '.SecretID')
    
    echo "CONSUL_VAULT_TOKEN=$vault_token" >> "/tmp/consul-service-tokens-$env.env"
    
    # Nomad service token
    local nomad_policy="nomad-policy-$env"
    consul acl policy create \
        -name "$nomad_policy" \
        -description "Policy for Nomad service in $env" \
        -rules 'agent_prefix "" { policy = "read" } node_prefix "" { policy = "read" } service_prefix "" { policy = "write" } acl = "write"'
    
    local nomad_token
    nomad_token=$(consul acl token create \
        -description "Nomad service token for $env" \
        -policy-name "$nomad_policy" \
        -format=json | jq -r '.SecretID')
    
    echo "CONSUL_NOMAD_TOKEN=$nomad_token" >> "/tmp/consul-service-tokens-$env.env"
    
    # Traefik service token
    local traefik_policy="traefik-policy-$env"
    consul acl policy create \
        -name "$traefik_policy" \
        -description "Policy for Traefik service in $env" \
        -rules 'service_prefix "" { policy = "read" } node_prefix "" { policy = "read" }'
    
    local traefik_token
    traefik_token=$(consul acl token create \
        -description "Traefik service token for $env" \
        -policy-name "$traefik_policy" \
        -format=json | jq -r '.SecretID')
    
    echo "CONSUL_TRAEFIK_TOKEN=$traefik_token" >> "/tmp/consul-service-tokens-$env.env"
    
    chmod 600 "/tmp/consul-service-tokens-$env.env"
    log "Service tokens created and saved to /tmp/consul-service-tokens-$env.env"
}

# Generate TLS certificates
generate_tls_certs() {
    local env="$1"
    local cert_dir="$CONSUL_DATA_DIR/tls"
    
    log "Generating TLS certificates for environment: $env"
    
    # Create certificate directory
    sudo mkdir -p "$cert_dir"
    
    # Generate CA
    consul tls ca create -domain "consul" -days 365
    
    # Generate server certificates
    consul tls cert create -server -dc "dc1-$env" -domain "consul" -days 365
    
    # Move certificates to proper location
    sudo mv consul-agent-ca.pem "$cert_dir/consul-ca.pem"
    sudo mv dc1-$env-server-consul-0.pem "$cert_dir/consul-cert.pem"
    sudo mv dc1-$env-server-consul-0-key.pem "$cert_dir/consul-key.pem"
    
    # Set proper permissions
    sudo chown -R consul:consul "$cert_dir"
    sudo chmod 644 "$cert_dir/consul-ca.pem" "$cert_dir/consul-cert.pem"
    sudo chmod 600 "$cert_dir/consul-key.pem"
    
    log "TLS certificates generated and installed"
}

# Validate Consul configuration
validate_config() {
    local config_file="$1"
    log "Validating Consul configuration: $config_file"
    
    if consul validate "$config_file"; then
        log "Configuration validation successful"
        return 0
    else
        error "Configuration validation failed"
        return 1
    fi
}

# Test DNS functionality
test_dns() {
    local env="$1"
    log "Testing DNS functionality for environment: $env"
    
    # Test basic DNS resolution
    if dig @127.0.0.1 -p 8600 consul.service.consul &>/dev/null; then
        log "DNS resolution test: PASSED"
    else
        log "DNS resolution test: FAILED"
    fi
    
    # Test service discovery
    local services
    if services=$(consul catalog services); then
        log "Service catalog accessible: PASSED"
        log "Registered services: $services"
    else
        log "Service catalog test: FAILED"
    fi
}

# Security health check
security_healthcheck() {
    local env="$1"
    log "Running security health check for environment: $env"
    
    local issues=0
    
    # Check ACL status
    if consul acl token read -self &>/dev/null; then
        log "ACL system: ENABLED"
    else
        log "WARNING: ACL system not properly configured"
        ((issues++))
    fi
    
    # Check TLS configuration
    if [[ -f "$CONSUL_DATA_DIR/tls/consul-cert.pem" ]]; then
        log "TLS certificates: PRESENT"
    else
        log "WARNING: TLS certificates not found"
        ((issues++))
    fi
    
    # Check gossip encryption
    if consul keyring -list | grep -q "Keys"; then
        log "Gossip encryption: ENABLED"
    else
        log "WARNING: Gossip encryption not configured"
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        log "Security health check: PASSED"
        return 0
    else
        log "Security health check: FAILED ($issues issues found)"
        return 1
    fi
}

# Token rotation
rotate_tokens() {
    local env="$1"
    log "Rotating service tokens for environment: $env"
    
    # Create backup of current tokens
    cp "/tmp/consul-service-tokens-$env.env" "/tmp/consul-service-tokens-$env.env.backup.$(date +%Y%m%d)"
    
    # Generate new tokens (reuse create_service_tokens function)
    create_service_tokens "$env"
    
    log "Token rotation completed. Old tokens backed up."
    log "WARNING: Update all services with new tokens!"
}

# Backup Consul data
backup_consul() {
    local env="$1"
    local backup_dir="/var/backups/consul"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    log "Creating Consul backup for environment: $env"
    
    sudo mkdir -p "$backup_dir"
    
    # Create snapshot
    consul snapshot save "$backup_dir/consul-snapshot-$env-$timestamp.snap"
    
    # Backup configuration
    sudo tar -czf "$backup_dir/consul-config-$env-$timestamp.tar.gz" -C "$CONSUL_CONFIG_DIR" .
    
    # Backup ACL tokens (if they exist)
    if [[ -f "/tmp/consul-service-tokens-$env.env" ]]; then
        sudo cp "/tmp/consul-service-tokens-$env.env" "$backup_dir/consul-tokens-$env-$timestamp.env"
    fi
    
    log "Backup created in $backup_dir"
}

# Main function
main() {
    local command="${1:-help}"
    local env="${2:-development}"
    
    # Ensure log file exists
    sudo touch "$LOG_FILE"
    sudo chown "$(whoami)" "$LOG_FILE"
    
    check_consul_binary
    
    case "$command" in
        "generate-key")
            generate_gossip_key
            ;;
        "bootstrap")
            bootstrap_acl "$env"
            ;;
        "create-tokens")
            create_service_tokens "$env"
            ;;
        "generate-certs")
            generate_tls_certs "$env"
            ;;
        "validate")
            local config_file="${3:-$CONSUL_CONFIG_DIR/consul-$env.hcl}"
            validate_config "$config_file"
            ;;
        "test-dns")
            test_dns "$env"
            ;;
        "healthcheck")
            security_healthcheck "$env"
            ;;
        "rotate-tokens")
            rotate_tokens "$env"
            ;;
        "backup")
            backup_consul "$env"
            ;;
        "full-setup")
            log "Running full security setup for environment: $env"
            generate_tls_certs "$env"
            bootstrap_acl "$env"
            create_service_tokens "$env"
            security_healthcheck "$env"
            ;;
        "help"|*)
            echo "Consul Security Automation Tool"
            echo "Usage: $0 [command] [environment]"
            echo ""
            echo "Commands:"
            echo "  generate-key     - Generate gossip encryption key"
            echo "  bootstrap        - Bootstrap ACL system"
            echo "  create-tokens    - Create service-specific tokens"
            echo "  generate-certs   - Generate TLS certificates"
            echo "  validate         - Validate configuration file"
            echo "  test-dns         - Test DNS functionality"
            echo "  healthcheck      - Run security health check"
            echo "  rotate-tokens    - Rotate service tokens"
            echo "  backup          - Create Consul backup"
            echo "  full-setup      - Run complete security setup"
            echo "  help            - Show this help message"
            echo ""
            echo "Environments: development, staging, production"
            ;;
    esac
}

# Run main function with all arguments
main "$@"