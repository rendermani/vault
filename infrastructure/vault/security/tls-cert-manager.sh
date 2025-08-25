#!/bin/bash

# TLS Certificate Management Script for Vault
# Handles certificate creation, renewal, and Let's Encrypt automation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_TLS_DIR="/etc/vault.d/tls"
BACKUP_DIR="/etc/vault.d/tls/backup"
VAULT_DOMAIN="${VAULT_DOMAIN:-cloudya.net}"
LE_EMAIL="${LE_EMAIL:-admin@cloudya.net}"
CERT_DAYS_WARNING=${CERT_DAYS_WARNING:-30}

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

# Ensure directories exist
setup_directories() {
    log_step "Setting up TLS directories..."
    
    mkdir -p "$VAULT_TLS_DIR" "$BACKUP_DIR"
    chmod 750 "$VAULT_TLS_DIR"
    chmod 700 "$BACKUP_DIR"
    
    # Set ownership if vault user exists
    if id vault &>/dev/null; then
        chown -R vault:vault "$VAULT_TLS_DIR"
    fi
    
    log_info "✅ Directories configured"
}

# Generate self-signed certificates for development/testing
generate_self_signed() {
    log_step "Generating self-signed certificates..."
    
    # Create CA key and certificate
    openssl genrsa -out "$VAULT_TLS_DIR/ca-key.pem" 4096
    openssl req -new -x509 -days 3650 -key "$VAULT_TLS_DIR/ca-key.pem" \
        -out "$VAULT_TLS_DIR/ca-cert.pem" \
        -subj "/C=US/ST=CA/L=SF/O=Vault-CA/OU=Security/CN=Vault-CA"
    
    # Create server key
    openssl genrsa -out "$VAULT_TLS_DIR/vault-key.pem" 4096
    
    # Create certificate signing request
    cat > "$VAULT_TLS_DIR/vault.csr.conf" << EOF
[req]
default_bits = 4096
prompt = no
distinguished_name = dn
req_extensions = v3_req

[dn]
C=US
ST=CA
L=San Francisco
O=Vault
OU=Security
CN=$VAULT_DOMAIN

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $VAULT_DOMAIN
DNS.2 = localhost
DNS.3 = vault.service.consul
IP.1 = 127.0.0.1
IP.2 = ::1
EOF
    
    # Generate certificate signing request
    openssl req -new -key "$VAULT_TLS_DIR/vault-key.pem" \
        -out "$VAULT_TLS_DIR/vault.csr" \
        -config "$VAULT_TLS_DIR/vault.csr.conf"
    
    # Sign the certificate with CA
    openssl x509 -req -in "$VAULT_TLS_DIR/vault.csr" \
        -CA "$VAULT_TLS_DIR/ca-cert.pem" \
        -CAkey "$VAULT_TLS_DIR/ca-key.pem" \
        -CAcreateserial \
        -out "$VAULT_TLS_DIR/vault-cert.pem" \
        -days 365 \
        -extensions v3_req \
        -extfile "$VAULT_TLS_DIR/vault.csr.conf"
    
    # Set appropriate permissions
    chmod 600 "$VAULT_TLS_DIR"/*.pem
    chmod 644 "$VAULT_TLS_DIR/ca-cert.pem" "$VAULT_TLS_DIR/vault-cert.pem"
    
    # Clean up CSR files
    rm -f "$VAULT_TLS_DIR/vault.csr" "$VAULT_TLS_DIR/vault.csr.conf"
    
    if id vault &>/dev/null; then
        chown vault:vault "$VAULT_TLS_DIR"/*.pem
    fi
    
    log_info "✅ Self-signed certificates generated"
    log_warn "⚠️  Remember to distribute CA certificate to clients: $VAULT_TLS_DIR/ca-cert.pem"
}

# Generate Let's Encrypt certificates
generate_letsencrypt() {
    log_step "Generating Let's Encrypt certificates..."
    
    # Check if certbot is installed
    if ! command -v certbot &> /dev/null; then
        log_error "certbot is not installed. Installing..."
        
        # Install certbot based on OS
        if [[ -f /etc/redhat-release ]]; then
            dnf install -y certbot
        elif [[ -f /etc/debian_version ]]; then
            apt-get update && apt-get install -y certbot
        else
            log_error "Unsupported OS for automatic certbot installation"
            exit 1
        fi
    fi
    
    # Stop vault temporarily if running
    VAULT_WAS_RUNNING=false
    if systemctl is-active --quiet vault; then
        VAULT_WAS_RUNNING=true
        log_warn "Stopping Vault temporarily for certificate generation..."
        systemctl stop vault
    fi
    
    # Generate certificate using standalone mode
    certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email "$LE_EMAIL" \
        --domains "$VAULT_DOMAIN" \
        --cert-path "$VAULT_TLS_DIR/vault-cert.pem" \
        --key-path "$VAULT_TLS_DIR/vault-key.pem" \
        --fullchain-path "$VAULT_TLS_DIR/vault-fullchain.pem" \
        --chain-path "$VAULT_TLS_DIR/vault-chain.pem"
    
    # Copy Let's Encrypt certificates to Vault directory
    if [[ -f "/etc/letsencrypt/live/$VAULT_DOMAIN/fullchain.pem" ]]; then
        cp "/etc/letsencrypt/live/$VAULT_DOMAIN/fullchain.pem" "$VAULT_TLS_DIR/vault-cert.pem"
        cp "/etc/letsencrypt/live/$VAULT_DOMAIN/privkey.pem" "$VAULT_TLS_DIR/vault-key.pem"
        cp "/etc/letsencrypt/live/$VAULT_DOMAIN/chain.pem" "$VAULT_TLS_DIR/ca-cert.pem"
        
        # Set appropriate permissions
        chmod 644 "$VAULT_TLS_DIR/vault-cert.pem" "$VAULT_TLS_DIR/ca-cert.pem"
        chmod 600 "$VAULT_TLS_DIR/vault-key.pem"
        
        if id vault &>/dev/null; then
            chown vault:vault "$VAULT_TLS_DIR"/*.pem
        fi
        
        log_info "✅ Let's Encrypt certificates installed"
    else
        log_error "Failed to obtain Let's Encrypt certificate"
        exit 1
    fi
    
    # Restart vault if it was running
    if [[ "$VAULT_WAS_RUNNING" == "true" ]]; then
        log_info "Restarting Vault..."
        systemctl start vault
        sleep 5
        systemctl is-active --quiet vault && log_info "✅ Vault restarted successfully"
    fi
}

# Setup automatic certificate renewal
setup_auto_renewal() {
    log_step "Setting up automatic certificate renewal..."
    
    # Create renewal script
    cat > "/usr/local/bin/vault-cert-renew.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

VAULT_TLS_DIR="/etc/vault.d/tls"
BACKUP_DIR="/etc/vault.d/tls/backup"
VAULT_DOMAIN="${VAULT_DOMAIN:-cloudya.net}"

log_info() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $1"; }
log_error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $1" >&2; }

# Backup current certificates
backup_cert() {
    local backup_name="backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR/$backup_name"
    
    if [[ -f "$VAULT_TLS_DIR/vault-cert.pem" ]]; then
        cp "$VAULT_TLS_DIR"/*.pem "$BACKUP_DIR/$backup_name/"
        log_info "Certificates backed up to $BACKUP_DIR/$backup_name"
    fi
}

# Renew Let's Encrypt certificate
renew_letsencrypt() {
    log_info "Attempting to renew Let's Encrypt certificate..."
    
    if certbot renew --quiet --no-self-upgrade; then
        log_info "Certificate renewal successful"
        
        # Backup old certificates
        backup_cert
        
        # Copy new certificates
        cp "/etc/letsencrypt/live/$VAULT_DOMAIN/fullchain.pem" "$VAULT_TLS_DIR/vault-cert.pem"
        cp "/etc/letsencrypt/live/$VAULT_DOMAIN/privkey.pem" "$VAULT_TLS_DIR/vault-key.pem"
        cp "/etc/letsencrypt/live/$VAULT_DOMAIN/chain.pem" "$VAULT_TLS_DIR/ca-cert.pem"
        
        # Set permissions
        chmod 644 "$VAULT_TLS_DIR/vault-cert.pem" "$VAULT_TLS_DIR/ca-cert.pem"
        chmod 600 "$VAULT_TLS_DIR/vault-key.pem"
        
        if id vault &>/dev/null; then
            chown vault:vault "$VAULT_TLS_DIR"/*.pem
        fi
        
        # Reload Vault to pick up new certificates
        systemctl reload vault || systemctl restart vault
        log_info "Vault reloaded with new certificates"
        
        # Send notification (customize as needed)
        echo "Vault TLS certificate renewed successfully" | \
            mail -s "Vault Certificate Renewal" admin@cloudya.net 2>/dev/null || true
    else
        log_error "Certificate renewal failed"
        exit 1
    fi
}

# Check certificate expiration
check_cert_expiration() {
    if [[ -f "$VAULT_TLS_DIR/vault-cert.pem" ]]; then
        local expiry_date=$(openssl x509 -enddate -noout -in "$VAULT_TLS_DIR/vault-cert.pem" | cut -d= -f2)
        local expiry_epoch=$(date -d "$expiry_date" +%s)
        local current_epoch=$(date +%s)
        local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
        
        log_info "Certificate expires in $days_until_expiry days"
        
        if [[ $days_until_expiry -le 30 ]]; then
            log_info "Certificate expires soon, attempting renewal..."
            renew_letsencrypt
        else
            log_info "Certificate is still valid"
        fi
    else
        log_error "Certificate file not found: $VAULT_TLS_DIR/vault-cert.pem"
        exit 1
    fi
}

# Run renewal check
check_cert_expiration
EOF

    chmod +x "/usr/local/bin/vault-cert-renew.sh"
    
    # Create systemd service for renewal
    cat > "/etc/systemd/system/vault-cert-renewal.service" << EOF
[Unit]
Description=Vault Certificate Renewal
After=network.target

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/vault-cert-renew.sh
Environment=VAULT_DOMAIN=$VAULT_DOMAIN
EOF

    # Create systemd timer for daily checks
    cat > "/etc/systemd/system/vault-cert-renewal.timer" << EOF
[Unit]
Description=Run Vault Certificate Renewal Daily
Requires=vault-cert-renewal.service

[Timer]
OnCalendar=daily
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Enable and start timer
    systemctl daemon-reload
    systemctl enable vault-cert-renewal.timer
    systemctl start vault-cert-renewal.timer
    
    log_info "✅ Automatic certificate renewal configured"
}

# Verify certificates
verify_certificates() {
    log_step "Verifying certificates..."
    
    local errors=0
    
    # Check if files exist
    for file in "vault-cert.pem" "vault-key.pem" "ca-cert.pem"; do
        if [[ ! -f "$VAULT_TLS_DIR/$file" ]]; then
            log_error "Missing certificate file: $file"
            ((errors++))
        fi
    done
    
    if [[ $errors -gt 0 ]]; then
        log_error "Certificate verification failed: missing files"
        return 1
    fi
    
    # Verify certificate validity
    if ! openssl x509 -in "$VAULT_TLS_DIR/vault-cert.pem" -text -noout &>/dev/null; then
        log_error "Invalid certificate format"
        ((errors++))
    fi
    
    # Verify private key
    if ! openssl rsa -in "$VAULT_TLS_DIR/vault-key.pem" -check -noout &>/dev/null; then
        log_error "Invalid private key format"
        ((errors++))
    fi
    
    # Verify certificate matches private key
    local cert_modulus=$(openssl x509 -noout -modulus -in "$VAULT_TLS_DIR/vault-cert.pem" | openssl md5)
    local key_modulus=$(openssl rsa -noout -modulus -in "$VAULT_TLS_DIR/vault-key.pem" | openssl md5)
    
    if [[ "$cert_modulus" != "$key_modulus" ]]; then
        log_error "Certificate and private key do not match"
        ((errors++))
    fi
    
    # Check certificate expiration
    local expiry_date=$(openssl x509 -enddate -noout -in "$VAULT_TLS_DIR/vault-cert.pem" | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s)
    local current_epoch=$(date +%s)
    local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    log_info "Certificate expires in $days_until_expiry days ($expiry_date)"
    
    if [[ $days_until_expiry -le 0 ]]; then
        log_error "Certificate has expired"
        ((errors++))
    elif [[ $days_until_expiry -le $CERT_DAYS_WARNING ]]; then
        log_warn "Certificate expires in $days_until_expiry days"
    fi
    
    # Check certificate subject alternative names
    local san=$(openssl x509 -noout -text -in "$VAULT_TLS_DIR/vault-cert.pem" | grep -A1 "Subject Alternative Name" | tail -1)
    log_info "Certificate SAN: $san"
    
    if [[ $errors -eq 0 ]]; then
        log_info "✅ Certificate verification passed"
        return 0
    else
        log_error "❌ Certificate verification failed with $errors errors"
        return 1
    fi
}

# Rotate certificates (backup current, generate new)
rotate_certificates() {
    log_step "Rotating certificates..."
    
    # Backup current certificates
    local backup_name="rotation-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR/$backup_name"
    
    if [[ -f "$VAULT_TLS_DIR/vault-cert.pem" ]]; then
        cp "$VAULT_TLS_DIR"/*.pem "$BACKUP_DIR/$backup_name/"
        log_info "Current certificates backed up to $BACKUP_DIR/$backup_name"
    fi
    
    # Generate new certificates (based on existing setup)
    if [[ -d "/etc/letsencrypt/live/$VAULT_DOMAIN" ]]; then
        generate_letsencrypt
    else
        generate_self_signed
    fi
    
    # Reload Vault
    if systemctl is-active --quiet vault; then
        systemctl reload vault || systemctl restart vault
        log_info "Vault reloaded with new certificates"
    fi
    
    log_info "✅ Certificate rotation completed"
}

# Show certificate information
show_cert_info() {
    if [[ -f "$VAULT_TLS_DIR/vault-cert.pem" ]]; then
        log_info "Certificate information:"
        openssl x509 -in "$VAULT_TLS_DIR/vault-cert.pem" -text -noout | head -20
        
        log_info "Certificate chain:"
        openssl x509 -in "$VAULT_TLS_DIR/vault-cert.pem" -issuer -noout
        
        log_info "Certificate fingerprint:"
        openssl x509 -in "$VAULT_TLS_DIR/vault-cert.pem" -fingerprint -noout
    else
        log_error "Certificate file not found: $VAULT_TLS_DIR/vault-cert.pem"
    fi
}

# Clean up old backups
cleanup_backups() {
    log_step "Cleaning up old certificate backups..."
    
    find "$BACKUP_DIR" -type d -name "backup-*" -mtime +90 -exec rm -rf {} \; 2>/dev/null || true
    find "$BACKUP_DIR" -type d -name "rotation-*" -mtime +90 -exec rm -rf {} \; 2>/dev/null || true
    
    local remaining_backups=$(find "$BACKUP_DIR" -type d -mindepth 1 | wc -l)
    log_info "✅ Cleanup completed. $remaining_backups backup(s) remaining"
}

# Main function
main() {
    case "${1:-help}" in
        setup)
            setup_directories
            ;;
        self-signed)
            setup_directories
            generate_self_signed
            verify_certificates
            ;;
        letsencrypt)
            setup_directories
            generate_letsencrypt
            setup_auto_renewal
            verify_certificates
            ;;
        renew)
            /usr/local/bin/vault-cert-renew.sh
            ;;
        rotate)
            rotate_certificates
            ;;
        verify)
            verify_certificates
            ;;
        info)
            show_cert_info
            ;;
        cleanup)
            cleanup_backups
            ;;
        help|*)
            cat << EOF
Vault TLS Certificate Manager

Usage: $0 <command>

Commands:
  setup       - Setup TLS directories
  self-signed - Generate self-signed certificates
  letsencrypt - Generate Let's Encrypt certificates
  renew       - Manually renew certificates
  rotate      - Rotate certificates (backup + generate new)
  verify      - Verify certificate validity
  info        - Show certificate information
  cleanup     - Clean up old certificate backups
  help        - Show this help message

Environment Variables:
  VAULT_DOMAIN        - Domain for certificates (default: cloudya.net)
  LE_EMAIL           - Email for Let's Encrypt (default: admin@cloudya.net)
  CERT_DAYS_WARNING  - Days before expiry to warn (default: 30)

Examples:
  $0 self-signed                    # Generate self-signed certs
  VAULT_DOMAIN=vault.example.com $0 letsencrypt  # LE certs for custom domain
  $0 verify                         # Check certificate validity
  $0 rotate                         # Rotate certificates
EOF
            ;;
    esac
}

# Run main function with all arguments
main "$@"