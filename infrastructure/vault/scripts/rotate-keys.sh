#!/bin/bash
# Vault Key Rotation Script
# Handles root token rotation and assists with unseal key rotation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
VAULT_ADDR=${VAULT_ADDR:-"http://127.0.0.1:8200"}
VAULT_DATA_DIR="/opt/vault"
BACKUP_DIR="/opt/vault/backups"
INIT_FILE="$VAULT_DATA_DIR/init.json"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Vault is installed
    if ! command -v vault &> /dev/null; then
        log_error "Vault is not installed"
        exit 1
    fi
    
    # Check if Vault is initialized
    if ! vault status 2>&1 | grep -q "Initialized.*true"; then
        log_error "Vault is not initialized"
        exit 1
    fi
    
    # Check if Vault is unsealed
    if vault status 2>&1 | grep -q "Sealed.*true"; then
        log_error "Vault is sealed. Please unseal it first:"
        echo "  vault operator unseal <key-1>"
        echo "  vault operator unseal <key-2>"
        echo "  vault operator unseal <key-3>"
        exit 1
    fi
    
    # Check if init file exists
    if [[ ! -f "$INIT_FILE" ]]; then
        log_error "Init file not found at $INIT_FILE"
        log_error "Cannot proceed without the initial root token"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Backup current keys
backup_keys() {
    log_info "Backing up current keys..."
    
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    BACKUP_PATH="$BACKUP_DIR/keys-$TIMESTAMP"
    mkdir -p "$BACKUP_PATH"
    
    # Backup init file
    cp "$INIT_FILE" "$BACKUP_PATH/init-backup.json"
    chmod 600 "$BACKUP_PATH/init-backup.json"
    
    # Create backup metadata
    cat > "$BACKUP_PATH/backup-metadata.txt" << EOF
Backup Created: $(date)
Backup Type: Key Rotation
Vault Version: $(vault version | head -1)
Operator: $USER
Reason: Key rotation operation
EOF
    
    log_success "Keys backed up to: $BACKUP_PATH"
    echo "$BACKUP_PATH"
}

# Rotate root token
rotate_root_token() {
    log_info "Starting root token rotation..."
    
    # Get current root token
    CURRENT_ROOT_TOKEN=$(jq -r '.root_token' "$INIT_FILE")
    
    if [[ -z "$CURRENT_ROOT_TOKEN" || "$CURRENT_ROOT_TOKEN" == "null" ]]; then
        log_error "No root token found in init file"
        log_warning "Root token may have already been rotated"
        return 1
    fi
    
    # Use current root token
    export VAULT_TOKEN="$CURRENT_ROOT_TOKEN"
    
    # Generate new root token
    log_info "Generating new root token..."
    NEW_ROOT_TOKEN=$(vault token create \
        -policy=root \
        -display-name="root-rotated-$(date +%Y%m%d)" \
        -format=json | jq -r '.auth.client_token')
    
    if [[ -z "$NEW_ROOT_TOKEN" ]]; then
        log_error "Failed to generate new root token"
        return 1
    fi
    
    # Update init file with new token
    jq --arg token "$NEW_ROOT_TOKEN" '.root_token = $token' "$INIT_FILE" > /tmp/init-new.json
    mv /tmp/init-new.json "$INIT_FILE"
    chmod 600 "$INIT_FILE"
    
    # Switch to new token
    export VAULT_TOKEN="$NEW_ROOT_TOKEN"
    
    # Revoke old root token
    log_info "Revoking old root token..."
    vault token revoke "$CURRENT_ROOT_TOKEN" || log_warning "Failed to revoke old token (may already be revoked)"
    
    log_success "Root token rotated successfully"
    log_warning "New root token saved to: $INIT_FILE"
    
    # Display new token (only in interactive mode)
    if [[ -t 1 ]]; then
        echo ""
        echo "New Root Token: $NEW_ROOT_TOKEN"
        echo ""
        log_warning "Store this token securely and remove from init file after saving"
    fi
}

# Initialize unseal key rotation
init_rekey() {
    log_info "Initializing unseal key rotation..."
    
    # Check if rekey is already in progress
    if vault operator rekey -status 2>&1 | grep -q "Rekey in progress.*true"; then
        log_warning "Rekey operation already in progress"
        vault operator rekey -status
        return 0
    fi
    
    # Initialize rekey operation
    log_info "Starting rekey operation with 5 shares and threshold of 3..."
    vault operator rekey -init -key-shares=5 -key-threshold=3 -format=json > /tmp/rekey-init.json
    
    NONCE=$(jq -r '.nonce' /tmp/rekey-init.json)
    
    if [[ -z "$NONCE" || "$NONCE" == "null" ]]; then
        log_error "Failed to initialize rekey operation"
        return 1
    fi
    
    log_success "Rekey operation initialized"
    log_info "Nonce: $NONCE"
    
    echo ""
    log_warning "IMPORTANT: You must now provide the current unseal keys"
    echo ""
    echo "Run the following commands with your current unseal keys:"
    echo ""
    echo "  vault operator rekey -nonce=$NONCE <unseal-key-1>"
    echo "  vault operator rekey -nonce=$NONCE <unseal-key-2>"
    echo "  vault operator rekey -nonce=$NONCE <unseal-key-3>"
    echo ""
    echo "After providing the threshold number of keys, new unseal keys will be generated."
    
    # Save nonce for reference
    echo "$NONCE" > /tmp/vault-rekey-nonce
    log_info "Nonce saved to: /tmp/vault-rekey-nonce"
}

# Cancel rekey operation
cancel_rekey() {
    log_info "Cancelling rekey operation..."
    
    if vault operator rekey -cancel; then
        log_success "Rekey operation cancelled"
    else
        log_warning "No rekey operation in progress or already cancelled"
    fi
}

# Check rekey status
check_rekey_status() {
    log_info "Checking rekey status..."
    vault operator rekey -status
}

# Interactive rekey process
interactive_rekey() {
    log_info "Starting interactive rekey process..."
    
    # Initialize rekey
    init_rekey
    
    # Get nonce
    NONCE=$(cat /tmp/vault-rekey-nonce 2>/dev/null)
    if [[ -z "$NONCE" ]]; then
        log_error "No nonce found. Please run init-rekey first."
        return 1
    fi
    
    # Prompt for unseal keys
    echo ""
    log_info "Please provide 3 unseal keys (threshold)"
    
    for i in 1 2 3; do
        echo -n "Enter unseal key $i: "
        read -s UNSEAL_KEY
        echo ""
        
        RESULT=$(vault operator rekey -nonce="$NONCE" "$UNSEAL_KEY" -format=json 2>/dev/null || echo "{}")
        
        COMPLETE=$(echo "$RESULT" | jq -r '.complete' 2>/dev/null)
        if [[ "$COMPLETE" == "true" ]]; then
            log_success "Rekey operation completed!"
            
            # Save new keys
            NEW_KEYS_FILE="$VAULT_DATA_DIR/new-unseal-keys-$(date +%Y%m%d-%H%M%S).json"
            echo "$RESULT" | jq '{unseal_keys_b64: .keys_base64, unseal_keys_hex: .keys}' > "$NEW_KEYS_FILE"
            chmod 600 "$NEW_KEYS_FILE"
            
            log_success "New unseal keys saved to: $NEW_KEYS_FILE"
            log_warning "CRITICAL: Distribute these keys securely and delete this file!"
            
            # Update init file with new keys
            jq --argjson keys "$RESULT" '.unseal_keys_b64 = $keys.keys_base64 | .unseal_keys_hex = $keys.keys' "$INIT_FILE" > /tmp/init-updated.json
            mv /tmp/init-updated.json "$INIT_FILE"
            chmod 600 "$INIT_FILE"
            
            return 0
        fi
        
        PROGRESS=$(echo "$RESULT" | jq -r '.progress' 2>/dev/null)
        log_info "Progress: $PROGRESS/3"
    done
    
    log_error "Rekey operation did not complete. Please check the status."
    check_rekey_status
}

# Generate recovery keys (for auto-unseal configurations)
generate_recovery_keys() {
    log_info "Generating recovery keys..."
    
    # Check if auto-unseal is configured
    if ! vault status 2>&1 | grep -q "Recovery Seal Type"; then
        log_warning "Auto-unseal not configured. Recovery keys not needed."
        return 0
    fi
    
    # Generate recovery keys
    vault operator generate-root -init -format=json > /tmp/recovery-init.json
    
    OTP=$(jq -r '.otp' /tmp/recovery-init.json)
    NONCE=$(jq -r '.nonce' /tmp/recovery-init.json)
    
    log_info "Recovery key generation initialized"
    log_info "OTP: $OTP"
    log_info "Nonce: $NONCE"
    
    # This would need the unseal/recovery keys to complete
    log_warning "To complete recovery key generation, provide unseal/recovery keys"
}

# Main menu
show_menu() {
    echo ""
    echo "========================================="
    echo "       Vault Key Rotation Tool"
    echo "========================================="
    echo "1. Rotate Root Token"
    echo "2. Initialize Unseal Key Rotation"
    echo "3. Interactive Unseal Key Rotation"
    echo "4. Check Rekey Status"
    echo "5. Cancel Rekey Operation"
    echo "6. Backup Current Keys"
    echo "7. Generate Recovery Keys (Auto-unseal)"
    echo "8. Full Key Rotation (Root + Unseal)"
    echo "9. Exit"
    echo "========================================="
    echo -n "Select an option: "
}

# Full rotation process
full_rotation() {
    log_info "Starting full key rotation process..."
    
    # Check prerequisites
    check_prerequisites
    
    # Backup current keys
    BACKUP_PATH=$(backup_keys)
    
    # Rotate root token
    if rotate_root_token; then
        log_success "Root token rotation completed"
    else
        log_error "Root token rotation failed"
        log_info "Backup available at: $BACKUP_PATH"
        return 1
    fi
    
    # Ask about unseal key rotation
    echo ""
    log_warning "Root token has been rotated."
    echo -n "Do you want to rotate unseal keys as well? (y/n): "
    read -r RESPONSE
    
    if [[ "$RESPONSE" == "y" || "$RESPONSE" == "Y" ]]; then
        interactive_rekey
    else
        log_info "Skipping unseal key rotation"
    fi
    
    log_success "Key rotation process completed"
    log_warning "Remember to:"
    echo "  1. Securely distribute new keys to key holders"
    echo "  2. Update any automated systems with new tokens"
    echo "  3. Delete temporary key files after secure storage"
    echo "  4. Test unsealing with new keys"
}

# Parse command line arguments
case "${1:-}" in
    --root-only)
        check_prerequisites
        backup_keys
        rotate_root_token
        ;;
    --unseal-only)
        check_prerequisites
        backup_keys
        interactive_rekey
        ;;
    --full)
        full_rotation
        ;;
    --backup)
        backup_keys
        ;;
    --status)
        check_rekey_status
        ;;
    --cancel)
        cancel_rekey
        ;;
    --help)
        echo "Usage: $0 [option]"
        echo ""
        echo "Options:"
        echo "  --root-only    Rotate only the root token"
        echo "  --unseal-only  Rotate only the unseal keys"
        echo "  --full         Rotate both root token and unseal keys"
        echo "  --backup       Backup current keys"
        echo "  --status       Check rekey operation status"
        echo "  --cancel       Cancel current rekey operation"
        echo "  --help         Show this help message"
        echo ""
        echo "Interactive mode: Run without arguments for menu"
        ;;
    *)
        # Interactive mode
        while true; do
            show_menu
            read -r OPTION
            
            case $OPTION in
                1)
                    check_prerequisites
                    backup_keys
                    rotate_root_token
                    ;;
                2)
                    check_prerequisites
                    init_rekey
                    ;;
                3)
                    check_prerequisites
                    backup_keys
                    interactive_rekey
                    ;;
                4)
                    check_rekey_status
                    ;;
                5)
                    cancel_rekey
                    ;;
                6)
                    backup_keys
                    ;;
                7)
                    generate_recovery_keys
                    ;;
                8)
                    full_rotation
                    ;;
                9)
                    echo "Exiting..."
                    exit 0
                    ;;
                *)
                    log_error "Invalid option"
                    ;;
            esac
            
            echo ""
            echo -n "Press Enter to continue..."
            read -r
        done
        ;;
esac