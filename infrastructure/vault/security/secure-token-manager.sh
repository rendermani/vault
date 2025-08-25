#!/bin/bash

# Secure Token Management System for Vault
# Handles secure token storage, masking, distribution, and rotation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_SECURE_DIR="/etc/vault.d/secure"
VAULT_TOKENS_DIR="$VAULT_SECURE_DIR/tokens"
VAULT_KEYS_DIR="$VAULT_SECURE_DIR/keys"
BACKUP_DIR="$VAULT_SECURE_DIR/backup"
ENCRYPTION_KEY_FILE="$VAULT_KEYS_DIR/master.key"
VAULT_ADDR="${VAULT_ADDR:-https://127.0.0.1:8200}"

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

# Initialize secure storage
init_secure_storage() {
    log_step "Initializing secure token storage..."
    
    # Create secure directories
    mkdir -p "$VAULT_SECURE_DIR" "$VAULT_TOKENS_DIR" "$VAULT_KEYS_DIR" "$BACKUP_DIR"
    
    # Set strict permissions
    chmod 700 "$VAULT_SECURE_DIR"
    chmod 700 "$VAULT_TOKENS_DIR"
    chmod 700 "$VAULT_KEYS_DIR"
    chmod 700 "$BACKUP_DIR"
    
    # Set ownership if vault user exists
    if id vault &>/dev/null; then
        chown -R vault:vault "$VAULT_SECURE_DIR"
    fi
    
    # Generate master encryption key if it doesn't exist
    if [[ ! -f "$ENCRYPTION_KEY_FILE" ]]; then
        log_step "Generating master encryption key..."
        openssl rand -hex 32 > "$ENCRYPTION_KEY_FILE"
        chmod 600 "$ENCRYPTION_KEY_FILE"
        
        if id vault &>/dev/null; then
            chown vault:vault "$ENCRYPTION_KEY_FILE"
        fi
        
        log_info "✅ Master encryption key generated"
    fi
    
    log_info "✅ Secure storage initialized"
}

# Encrypt sensitive data
encrypt_data() {
    local data="$1"
    local output_file="$2"
    
    if [[ ! -f "$ENCRYPTION_KEY_FILE" ]]; then
        log_error "Master encryption key not found. Run 'init' first."
        return 1
    fi
    
    local key=$(cat "$ENCRYPTION_KEY_FILE")
    echo -n "$data" | openssl enc -aes-256-cbc -base64 -pbkdf2 -iter 100000 -pass pass:"$key" > "$output_file"
    chmod 600 "$output_file"
    
    if id vault &>/dev/null; then
        chown vault:vault "$output_file"
    fi
}

# Decrypt sensitive data
decrypt_data() {
    local input_file="$1"
    
    if [[ ! -f "$ENCRYPTION_KEY_FILE" ]]; then
        log_error "Master encryption key not found."
        return 1
    fi
    
    if [[ ! -f "$input_file" ]]; then
        log_error "Encrypted file not found: $input_file"
        return 1
    fi
    
    local key=$(cat "$ENCRYPTION_KEY_FILE")
    openssl enc -aes-256-cbc -d -base64 -pbkdf2 -iter 100000 -pass pass:"$key" -in "$input_file"
}

# Store token securely
store_token() {
    local token_name="$1"
    local token_value="$2"
    local description="${3:-}"
    
    log_step "Storing token: $token_name"
    
    local token_file="$VAULT_TOKENS_DIR/$token_name.enc"
    local metadata_file="$VAULT_TOKENS_DIR/$token_name.meta"
    
    # Encrypt and store token
    encrypt_data "$token_value" "$token_file"
    
    # Store metadata
    cat > "$metadata_file" << EOF
{
  "name": "$token_name",
  "description": "$description",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "last_accessed": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "access_count": 0,
  "token_hash": "$(echo -n "$token_value" | sha256sum | cut -d' ' -f1)"
}
EOF
    
    chmod 600 "$metadata_file"
    if id vault &>/dev/null; then
        chown vault:vault "$metadata_file"
    fi
    
    log_info "✅ Token '$token_name' stored securely"
}

# Retrieve token
retrieve_token() {
    local token_name="$1"
    local silent="${2:-false}"
    
    local token_file="$VAULT_TOKENS_DIR/$token_name.enc"
    local metadata_file="$VAULT_TOKENS_DIR/$token_name.meta"
    
    if [[ ! -f "$token_file" ]]; then
        if [[ "$silent" != "true" ]]; then
            log_error "Token not found: $token_name"
        fi
        return 1
    fi
    
    # Update access metadata
    if [[ -f "$metadata_file" ]]; then
        local access_count=$(jq -r '.access_count' "$metadata_file" 2>/dev/null || echo "0")
        local new_count=$((access_count + 1))
        
        jq --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg count "$new_count" \
           '.last_accessed = $timestamp | .access_count = ($count | tonumber)' \
           "$metadata_file" > "${metadata_file}.tmp" && mv "${metadata_file}.tmp" "$metadata_file"
    fi
    
    decrypt_data "$token_file"
}

# Mask sensitive tokens in logs
mask_token() {
    local token="$1"
    local prefix_len="${2:-8}"
    local suffix_len="${3:-4}"
    
    if [[ ${#token} -le $((prefix_len + suffix_len + 3)) ]]; then
        echo "${token:0:4}***"
    else
        local prefix="${token:0:$prefix_len}"
        local suffix="${token: -$suffix_len}"
        echo "${prefix}***${suffix}"
    fi
}

# List stored tokens
list_tokens() {
    log_step "Listing stored tokens..."
    
    if [[ ! -d "$VAULT_TOKENS_DIR" ]]; then
        log_warn "Token storage directory not found"
        return 1
    fi
    
    local found=false
    for meta_file in "$VAULT_TOKENS_DIR"/*.meta; do
        [[ ! -f "$meta_file" ]] && continue
        
        found=true
        local token_name=$(basename "$meta_file" .meta)
        local description=$(jq -r '.description // "No description"' "$meta_file" 2>/dev/null)
        local created=$(jq -r '.created // "Unknown"' "$meta_file" 2>/dev/null)
        local last_accessed=$(jq -r '.last_accessed // "Never"' "$meta_file" 2>/dev/null)
        local access_count=$(jq -r '.access_count // 0' "$meta_file" 2>/dev/null)
        
        printf "%-20s %-30s %-20s %-20s %s\n" \
            "$token_name" \
            "$description" \
            "$created" \
            "$last_accessed" \
            "$access_count accesses"
    done
    
    if [[ "$found" == "false" ]]; then
        log_info "No tokens found"
    fi
}

# Delete token
delete_token() {
    local token_name="$1"
    local force="${2:-false}"
    
    local token_file="$VAULT_TOKENS_DIR/$token_name.enc"
    local metadata_file="$VAULT_TOKENS_DIR/$token_name.meta"
    
    if [[ ! -f "$token_file" ]]; then
        log_error "Token not found: $token_name"
        return 1
    fi
    
    if [[ "$force" != "true" ]]; then
        read -p "Are you sure you want to delete token '$token_name'? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deletion cancelled"
            return 0
        fi
    fi
    
    # Backup before deletion
    local backup_name="deleted-$token_name-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR/$backup_name"
    cp "$token_file" "$BACKUP_DIR/$backup_name/"
    [[ -f "$metadata_file" ]] && cp "$metadata_file" "$BACKUP_DIR/$backup_name/"
    
    # Delete files
    rm -f "$token_file" "$metadata_file"
    
    log_info "✅ Token '$token_name' deleted (backed up to $backup_name)"
}

# Rotate token
rotate_token() {
    local token_name="$1"
    local new_token="$2"
    local description="${3:-}"
    
    log_step "Rotating token: $token_name"
    
    # Backup current token
    local backup_name="rotation-$token_name-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR/$backup_name"
    
    local token_file="$VAULT_TOKENS_DIR/$token_name.enc"
    local metadata_file="$VAULT_TOKENS_DIR/$token_name.meta"
    
    if [[ -f "$token_file" ]]; then
        cp "$token_file" "$BACKUP_DIR/$backup_name/"
        [[ -f "$metadata_file" ]] && cp "$metadata_file" "$BACKUP_DIR/$backup_name/"
        
        log_info "Previous token backed up to $backup_name"
    fi
    
    # Store new token
    store_token "$token_name" "$new_token" "$description"
    
    log_info "✅ Token '$token_name' rotated successfully"
}

# Distribute token securely
distribute_token() {
    local token_name="$1"
    local target_host="$2"
    local target_path="$3"
    local ssh_key="${4:-}"
    
    log_step "Distributing token '$token_name' to $target_host:$target_path"
    
    local token_value=$(retrieve_token "$token_name" true)
    if [[ $? -ne 0 ]]; then
        log_error "Failed to retrieve token: $token_name"
        return 1
    fi
    
    # Create temporary encrypted file for transfer
    local temp_file=$(mktemp)
    encrypt_data "$token_value" "$temp_file"
    
    # Transfer using scp
    local scp_cmd="scp"
    if [[ -n "$ssh_key" ]]; then
        scp_cmd="scp -i $ssh_key"
    fi
    
    if $scp_cmd "$temp_file" "$target_host:$target_path.enc"; then
        log_info "✅ Token distributed successfully"
        
        # Send decryption instructions
        log_info "Decryption command for remote host:"
        log_info "openssl enc -aes-256-cbc -d -base64 -pbkdf2 -iter 100000 -pass pass:\"$(cat $ENCRYPTION_KEY_FILE)\" -in $target_path.enc -out $target_path"
    else
        log_error "Failed to distribute token"
        rm -f "$temp_file"
        return 1
    fi
    
    # Clean up
    rm -f "$temp_file"
}

# Generate secure random token
generate_token() {
    local length="${1:-32}"
    openssl rand -hex "$length"
}

# Validate token format
validate_token() {
    local token="$1"
    
    # Basic validation - customize based on your token format
    if [[ ${#token} -lt 8 ]]; then
        log_error "Token too short (minimum 8 characters)"
        return 1
    fi
    
    if [[ ! "$token" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        log_error "Token contains invalid characters"
        return 1
    fi
    
    return 0
}

# Create secure environment file
create_env_file() {
    local env_file="$1"
    shift
    local token_names=("$@")
    
    log_step "Creating secure environment file: $env_file"
    
    # Create temporary file
    local temp_file=$(mktemp)
    
    for token_name in "${token_names[@]}"; do
        local token_value=$(retrieve_token "$token_name" true)
        if [[ $? -eq 0 ]]; then
            echo "export ${token_name^^}=\"$token_value\"" >> "$temp_file"
        else
            log_warn "Token not found: $token_name"
        fi
    done
    
    # Encrypt environment file
    encrypt_data "$(cat $temp_file)" "$env_file"
    rm -f "$temp_file"
    
    log_info "✅ Secure environment file created: $env_file"
    log_info "Source with: source <($(dirname $0)/secure-token-manager.sh decrypt-env $env_file)"
}

# Decrypt environment file for sourcing
decrypt_env_file() {
    local env_file="$1"
    decrypt_data "$env_file"
}

# Monitor token usage
monitor_tokens() {
    log_step "Token usage monitoring..."
    
    local total_tokens=0
    local total_accesses=0
    local unused_tokens=0
    
    for meta_file in "$VAULT_TOKENS_DIR"/*.meta; do
        [[ ! -f "$meta_file" ]] && continue
        
        total_tokens=$((total_tokens + 1))
        local access_count=$(jq -r '.access_count // 0' "$meta_file" 2>/dev/null)
        total_accesses=$((total_accesses + access_count))
        
        if [[ $access_count -eq 0 ]]; then
            unused_tokens=$((unused_tokens + 1))
        fi
        
        # Check for old unused tokens
        local created=$(jq -r '.created // ""' "$meta_file" 2>/dev/null)
        if [[ -n "$created" ]]; then
            local created_epoch=$(date -d "$created" +%s 2>/dev/null || echo "0")
            local current_epoch=$(date +%s)
            local days_old=$(( (current_epoch - created_epoch) / 86400 ))
            
            if [[ $access_count -eq 0 && $days_old -gt 30 ]]; then
                local token_name=$(basename "$meta_file" .meta)
                log_warn "Unused token older than 30 days: $token_name (created $days_old days ago)"
            fi
        fi
    done
    
    log_info "Token Statistics:"
    log_info "  Total tokens: $total_tokens"
    log_info "  Total accesses: $total_accesses"
    log_info "  Unused tokens: $unused_tokens"
    
    if [[ $unused_tokens -gt 0 ]]; then
        log_warn "Consider reviewing unused tokens for cleanup"
    fi
}

# Backup tokens
backup_tokens() {
    local backup_name="tokens-backup-$(date +%Y%m%d-%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    log_step "Creating token backup: $backup_name"
    
    mkdir -p "$backup_path"
    
    # Copy all token files
    cp -r "$VAULT_TOKENS_DIR"/* "$backup_path/" 2>/dev/null || true
    
    # Copy encryption key
    cp "$ENCRYPTION_KEY_FILE" "$backup_path/"
    
    # Create backup metadata
    cat > "$backup_path/backup.meta" << EOF
{
  "backup_name": "$backup_name",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "$(hostname)",
  "token_count": $(find "$VAULT_TOKENS_DIR" -name "*.enc" | wc -l)
}
EOF
    
    # Create compressed archive
    tar -czf "$backup_path.tar.gz" -C "$BACKUP_DIR" "$backup_name"
    rm -rf "$backup_path"
    
    log_info "✅ Token backup created: $backup_path.tar.gz"
}

# Restore tokens from backup
restore_tokens() {
    local backup_file="$1"
    local force="${2:-false}"
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi
    
    log_step "Restoring tokens from backup: $backup_file"
    
    if [[ "$force" != "true" ]]; then
        read -p "This will overwrite existing tokens. Continue? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Restore cancelled"
            return 0
        fi
    fi
    
    # Create current backup before restore
    backup_tokens
    
    # Extract backup
    local temp_dir=$(mktemp -d)
    tar -xzf "$backup_file" -C "$temp_dir"
    
    # Find extracted directory
    local extracted_dir=$(find "$temp_dir" -name "tokens-backup-*" -type d | head -1)
    
    if [[ -z "$extracted_dir" ]]; then
        log_error "Invalid backup file format"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Restore files
    rm -rf "$VAULT_TOKENS_DIR"/*
    cp -r "$extracted_dir"/* "$VAULT_TOKENS_DIR/"
    
    # Restore encryption key if it exists in backup
    if [[ -f "$extracted_dir/master.key" ]]; then
        cp "$extracted_dir/master.key" "$ENCRYPTION_KEY_FILE"
    fi
    
    # Set permissions
    chmod 600 "$VAULT_TOKENS_DIR"/*
    if id vault &>/dev/null; then
        chown -R vault:vault "$VAULT_TOKENS_DIR"
        chown vault:vault "$ENCRYPTION_KEY_FILE"
    fi
    
    # Clean up
    rm -rf "$temp_dir"
    
    log_info "✅ Tokens restored from backup"
    
    # Show restored tokens
    list_tokens
}

# Clean up old backups
cleanup_backups() {
    log_step "Cleaning up old token backups..."
    
    find "$BACKUP_DIR" -name "tokens-backup-*.tar.gz" -mtime +90 -delete
    find "$BACKUP_DIR" -type d -name "deleted-*" -mtime +365 -exec rm -rf {} \;
    find "$BACKUP_DIR" -type d -name "rotation-*" -mtime +90 -exec rm -rf {} \;
    
    local remaining_backups=$(find "$BACKUP_DIR" -name "tokens-backup-*.tar.gz" | wc -l)
    log_info "✅ Cleanup completed. $remaining_backups backup(s) remaining"
}

# Main function
main() {
    case "${1:-help}" in
        init)
            init_secure_storage
            ;;
        store)
            [[ $# -lt 3 ]] && { log_error "Usage: $0 store <name> <token> [description]"; exit 1; }
            validate_token "$3" && store_token "$2" "$3" "${4:-}"
            ;;
        retrieve)
            [[ $# -lt 2 ]] && { log_error "Usage: $0 retrieve <name>"; exit 1; }
            retrieve_token "$2"
            ;;
        list)
            list_tokens
            ;;
        delete)
            [[ $# -lt 2 ]] && { log_error "Usage: $0 delete <name> [force]"; exit 1; }
            delete_token "$2" "${3:-false}"
            ;;
        rotate)
            [[ $# -lt 3 ]] && { log_error "Usage: $0 rotate <name> <new_token> [description]"; exit 1; }
            validate_token "$3" && rotate_token "$2" "$3" "${4:-}"
            ;;
        distribute)
            [[ $# -lt 4 ]] && { log_error "Usage: $0 distribute <name> <host> <path> [ssh_key]"; exit 1; }
            distribute_token "$2" "$3" "$4" "${5:-}"
            ;;
        generate)
            generate_token "${2:-32}"
            ;;
        mask)
            [[ $# -lt 2 ]] && { log_error "Usage: $0 mask <token> [prefix_len] [suffix_len]"; exit 1; }
            mask_token "$2" "${3:-8}" "${4:-4}"
            ;;
        create-env)
            [[ $# -lt 2 ]] && { log_error "Usage: $0 create-env <env_file> <token_name1> [token_name2] ..."; exit 1; }
            shift 2
            create_env_file "$1" "$@"
            ;;
        decrypt-env)
            [[ $# -lt 2 ]] && { log_error "Usage: $0 decrypt-env <env_file>"; exit 1; }
            decrypt_env_file "$2"
            ;;
        monitor)
            monitor_tokens
            ;;
        backup)
            backup_tokens
            ;;
        restore)
            [[ $# -lt 2 ]] && { log_error "Usage: $0 restore <backup_file> [force]"; exit 1; }
            restore_tokens "$2" "${3:-false}"
            ;;
        cleanup)
            cleanup_backups
            ;;
        help|*)
            cat << EOF
Secure Token Manager for Vault

Usage: $0 <command> [arguments]

Commands:
  init                                    - Initialize secure storage
  store <name> <token> [description]     - Store token securely
  retrieve <name>                         - Retrieve stored token
  list                                    - List all stored tokens
  delete <name> [force]                   - Delete stored token
  rotate <name> <new_token> [desc]        - Rotate token (backup old + store new)
  distribute <name> <host> <path> [key]   - Distribute token to remote host
  generate [length]                       - Generate secure random token
  mask <token> [prefix] [suffix]          - Mask token for logging
  create-env <file> <token1> [token2...]  - Create encrypted environment file
  decrypt-env <file>                      - Decrypt environment file for sourcing
  monitor                                 - Monitor token usage statistics
  backup                                  - Create backup of all tokens
  restore <backup_file> [force]           - Restore tokens from backup
  cleanup                                 - Clean up old backups
  help                                    - Show this help message

Examples:
  $0 init                                 # Initialize secure storage
  $0 store root-token hvs.XXXXXX         # Store root token
  $0 retrieve root-token                  # Get root token
  $0 generate 64                          # Generate 64-character token
  $0 mask "hvs.XXXXXX"                   # Mask token for logs
  $0 rotate root-token \$(vault write -field=token auth/token/create)
  
Environment Variables:
  VAULT_ADDR      - Vault server address (default: https://127.0.0.1:8200)
EOF
            ;;
    esac
}

# Run main function with all arguments
main "$@"