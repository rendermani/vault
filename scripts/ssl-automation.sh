#!/usr/bin/env bash
# SSL Certificate Automation
# Configures proper SSL certificates with CA validation and client certificates
#
# This script addresses HIGH/MEDIUM findings:
# - Missing TLS Client Certificate Verification
# - Weak TLS Configuration
# - SSL Certificate validation issues

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="/var/log/cloudya-security"
VAULT_ADDR="${VAULT_ADDR:-https://vault.cloudya.net:8200}"
DOMAIN="${DOMAIN:-cloudya.net}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[SSL-AUTOMATION]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_DIR/ssl-automation.log"
}

log_success() {
    echo -e "${GREEN}[SSL-AUTOMATION]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_DIR/ssl-automation.log"
}

log_error() {
    echo -e "${RED}[SSL-AUTOMATION]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_DIR/ssl-automation.log" >&2
}

# Setup PKI infrastructure in Vault
setup_pki_infrastructure() {
    log_info "Setting up PKI infrastructure in Vault..."
    
    # Enable PKI secrets engine for root CA
    vault secrets enable -path=pki pki 2>/dev/null || log_info "PKI engine already enabled"
    
    # Set max lease TTL for root CA (10 years)
    vault secrets tune -max-lease-ttl=87600h pki
    
    # Generate root CA certificate
    if ! vault read pki/cert/ca >/dev/null 2>&1; then
        vault write -field=certificate pki/root/generate/internal \
            common_name="CloudYa Root CA" \
            issuer_name="cloudya-root" \
            ttl=87600h > "$PROJECT_ROOT/automation/ssl-certs/root-ca.crt"
        
        log_success "Root CA certificate generated"
    else
        log_info "Root CA already exists"
        vault read -field=certificate pki/cert/ca > "$PROJECT_ROOT/automation/ssl-certs/root-ca.crt"
    fi
    
    # Configure CA and CRL URLs
    vault write pki/config/urls \
        issuing_certificates="$VAULT_ADDR/v1/pki/ca" \
        crl_distribution_points="$VAULT_ADDR/v1/pki/crl"
    
    log_success "PKI root CA infrastructure configured"
}

# Setup intermediate CA
setup_intermediate_ca() {
    log_info "Setting up intermediate CA..."
    
    # Enable intermediate PKI engine
    vault secrets enable -path=pki_int pki 2>/dev/null || log_info "Intermediate PKI engine already enabled"
    
    # Set max lease TTL for intermediate CA (5 years)
    vault secrets tune -max-lease-ttl=43800h pki_int
    
    # Generate intermediate CSR
    local csr_file="/tmp/pki_intermediate.csr"
    if ! vault read pki_int/cert/ca >/dev/null 2>&1; then
        vault write -format=json pki_int/intermediate/generate/internal \
            common_name="CloudYa Intermediate CA" \
            issuer_name="cloudya-intermediate" \
            | jq -r '.data.csr' > "$csr_file"
        
        # Sign intermediate CSR with root CA
        local signed_cert=$(vault write -format=json pki/root/sign-intermediate \
            csr=@"$csr_file" \
            format=pem_bundle \
            ttl="43800h" | jq -r '.data.certificate')
        
        # Set signed certificate back to intermediate CA
        echo "$signed_cert" | vault write pki_int/intermediate/set-signed certificate=-
        
        rm "$csr_file"
        log_success "Intermediate CA configured and signed"
    else
        log_info "Intermediate CA already exists"
    fi
    
    # Configure intermediate CA URLs
    vault write pki_int/config/urls \
        issuing_certificates="$VAULT_ADDR/v1/pki_int/ca" \
        crl_distribution_points="$VAULT_ADDR/v1/pki_int/crl"
    
    log_success "Intermediate CA infrastructure configured"
}

# Create certificate roles
create_certificate_roles() {
    log_info "Creating certificate roles..."
    
    # Server certificate role for CloudYa services
    vault write pki_int/roles/cloudya-server \
        issuer_ref="$(vault read -field=default pki_int/config/issuers)" \
        allowed_domains="$DOMAIN" \
        allowed_domains="localhost" \
        allowed_domains="127.0.0.1" \
        allow_subdomains=true \
        allow_localhost=true \
        allow_ip_sans=true \
        max_ttl="8760h" \
        ttl="720h" \
        server_flag=true \
        client_flag=false \
        key_type="ec" \
        key_bits="256" \
        key_usage="DigitalSignature,KeyEncipherment" \
        ext_key_usage="ServerAuth"
    
    # Client certificate role for mutual TLS
    vault write pki_int/roles/cloudya-client \
        issuer_ref="$(vault read -field=default pki_int/config/issuers)" \
        allowed_domains="$DOMAIN" \
        allow_subdomains=true \
        max_ttl="8760h" \
        ttl="720h" \
        server_flag=false \
        client_flag=true \
        key_type="ec" \
        key_bits="256" \
        key_usage="DigitalSignature,KeyEncipherment" \
        ext_key_usage="ClientAuth"
    
    # Service certificate role (both server and client)
    vault write pki_int/roles/cloudya-service \
        issuer_ref="$(vault read -field=default pki_int/config/issuers)" \
        allowed_domains="$DOMAIN" \
        allowed_domains="localhost" \
        allow_subdomains=true \
        allow_localhost=true \
        allow_ip_sans=true \
        max_ttl="8760h" \
        ttl="720h" \
        server_flag=true \
        client_flag=true \
        key_type="ec" \
        key_bits="256" \
        key_usage="DigitalSignature,KeyEncipherment" \
        ext_key_usage="ServerAuth,ClientAuth"
    
    log_success "Certificate roles created"
}

# Generate service certificates
generate_service_certificates() {
    log_info "Generating service certificates..."
    
    mkdir -p "$PROJECT_ROOT/automation/ssl-certs/services"
    
    # Vault server certificate
    vault write -format=json pki_int/issue/cloudya-server \
        common_name="vault.$DOMAIN" \
        alt_names="vault,localhost" \
        ip_sans="127.0.0.1,172.25.0.20" \
        ttl="720h" > "/tmp/vault-cert.json"
    
    jq -r '.data.certificate' "/tmp/vault-cert.json" > "$PROJECT_ROOT/automation/ssl-certs/services/vault.crt"
    jq -r '.data.private_key' "/tmp/vault-cert.json" > "$PROJECT_ROOT/automation/ssl-certs/services/vault.key"
    jq -r '.data.ca_chain[]' "/tmp/vault-cert.json" > "$PROJECT_ROOT/automation/ssl-certs/services/vault-ca.crt"
    
    # Consul server certificate
    vault write -format=json pki_int/issue/cloudya-server \
        common_name="consul.$DOMAIN" \
        alt_names="consul,localhost" \
        ip_sans="127.0.0.1,172.25.0.10" \
        ttl="720h" > "/tmp/consul-cert.json"
    
    jq -r '.data.certificate' "/tmp/consul-cert.json" > "$PROJECT_ROOT/automation/ssl-certs/services/consul.crt"
    jq -r '.data.private_key' "/tmp/consul-cert.json" > "$PROJECT_ROOT/automation/ssl-certs/services/consul.key"
    jq -r '.data.ca_chain[]' "/tmp/consul-cert.json" > "$PROJECT_ROOT/automation/ssl-certs/services/consul-ca.crt"
    
    # Nomad server certificate
    vault write -format=json pki_int/issue/cloudya-server \
        common_name="nomad.$DOMAIN" \
        alt_names="nomad,localhost" \
        ip_sans="127.0.0.1,172.25.0.30" \
        ttl="720h" > "/tmp/nomad-cert.json"
    
    jq -r '.data.certificate' "/tmp/nomad-cert.json" > "$PROJECT_ROOT/automation/ssl-certs/services/nomad.crt"
    jq -r '.data.private_key' "/tmp/nomad-cert.json" > "$PROJECT_ROOT/automation/ssl-certs/services/nomad.key"
    jq -r '.data.ca_chain[]' "/tmp/nomad-cert.json" > "$PROJECT_ROOT/automation/ssl-certs/services/nomad-ca.crt"
    
    # Traefik certificate
    vault write -format=json pki_int/issue/cloudya-server \
        common_name="traefik.$DOMAIN" \
        alt_names="traefik,localhost" \
        ip_sans="127.0.0.1" \
        ttl="720h" > "/tmp/traefik-cert.json"
    
    jq -r '.data.certificate' "/tmp/traefik-cert.json" > "$PROJECT_ROOT/automation/ssl-certs/services/traefik.crt"
    jq -r '.data.private_key' "/tmp/traefik-cert.json" > "$PROJECT_ROOT/automation/ssl-certs/services/traefik.key"
    jq -r '.data.ca_chain[]' "/tmp/traefik-cert.json" > "$PROJECT_ROOT/automation/ssl-certs/services/traefik-ca.crt"
    
    # Set proper permissions
    chmod 600 "$PROJECT_ROOT/automation/ssl-certs/services/"*.key
    chmod 644 "$PROJECT_ROOT/automation/ssl-certs/services/"*.crt
    
    # Cleanup
    rm -f /tmp/*-cert.json
    
    log_success "Service certificates generated"
}

# Generate client certificates for mutual TLS
generate_client_certificates() {
    log_info "Generating client certificates for mutual TLS..."
    
    mkdir -p "$PROJECT_ROOT/automation/ssl-certs/clients"
    
    # Admin client certificate
    vault write -format=json pki_int/issue/cloudya-client \
        common_name="admin-client.$DOMAIN" \
        ttl="8760h" > "/tmp/admin-client-cert.json"
    
    jq -r '.data.certificate' "/tmp/admin-client-cert.json" > "$PROJECT_ROOT/automation/ssl-certs/clients/admin-client.crt"
    jq -r '.data.private_key' "/tmp/admin-client-cert.json" > "$PROJECT_ROOT/automation/ssl-certs/clients/admin-client.key"
    jq -r '.data.ca_chain[]' "/tmp/admin-client-cert.json" > "$PROJECT_ROOT/automation/ssl-certs/clients/admin-client-ca.crt"
    
    # Service client certificates
    for service in nomad consul traefik; do
        vault write -format=json pki_int/issue/cloudya-client \
            common_name="${service}-client.$DOMAIN" \
            ttl="720h" > "/tmp/${service}-client-cert.json"
        
        jq -r '.data.certificate' "/tmp/${service}-client-cert.json" > "$PROJECT_ROOT/automation/ssl-certs/clients/${service}-client.crt"
        jq -r '.data.private_key' "/tmp/${service}-client-cert.json" > "$PROJECT_ROOT/automation/ssl-certs/clients/${service}-client.key"
    done
    
    # Set proper permissions
    chmod 600 "$PROJECT_ROOT/automation/ssl-certs/clients/"*.key
    chmod 644 "$PROJECT_ROOT/automation/ssl-certs/clients/"*.crt
    
    # Cleanup
    rm -f /tmp/*-client-cert.json
    
    log_success "Client certificates generated"
}

# Update Vault configuration for proper TLS
update_vault_tls_config() {
    log_info "Updating Vault TLS configuration..."
    
    local vault_config="$PROJECT_ROOT/infrastructure/vault/config/vault.hcl"
    local backup_config="${vault_config}.ssl-backup"
    
    # Backup original config
    cp "$vault_config" "$backup_config"
    
    # Create enhanced TLS configuration
    cat > /tmp/vault-tls-config.hcl << EOF
# Enhanced TLS Configuration
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/vault/certs/vault.crt"
  tls_key_file  = "/vault/certs/vault.key"
  tls_ca_file   = "/vault/certs/vault-ca.crt"
  
  # Enhanced TLS security
  tls_require_and_verify_client_cert = true
  tls_client_ca_file = "/vault/certs/vault-ca.crt"
  tls_min_version = "tls13"
  tls_prefer_server_cipher_suites = true
  
  # Strong cipher suites (TLS 1.3)
  tls_cipher_suites = "TLS_AES_256_GCM_SHA384,TLS_CHACHA20_POLY1305_SHA256,TLS_AES_128_GCM_SHA256"
  
  # Security headers
  tls_disable_client_certs = false
}

# Auto-unseal configuration (requires cloud KMS)
seal "transit" {
  address         = "$VAULT_ADDR"
  token           = "hvs.CAES..."  # Use actual token from secret
  disable_renewal = "false"
  key_name        = "autounseal"
  mount_path      = "transit/"
}

# Storage backend with TLS
storage "consul" {
  address = "consul.$DOMAIN:8500"
  path    = "vault/"
  scheme  = "https"
  
  # TLS configuration for Consul
  tls_ca_file   = "/vault/certs/consul-ca.crt"
  tls_cert_file = "/vault/certs/consul-client.crt"
  tls_key_file  = "/vault/certs/consul-client.key"
}

# API address with HTTPS
api_addr = "https://vault.$DOMAIN:8200"
cluster_addr = "https://vault.$DOMAIN:8201"

# Enhanced security settings
ui = false  # Disable UI in production
max_lease_ttl = "768h"
default_lease_ttl = "24h"

# Telemetry with TLS
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname = true
  
  # Secure telemetry endpoint
  unauthenticated_metrics_access = false
}

# Enhanced audit logging
audit "file" {
  file_path = "/vault/logs/audit.log"
  log_raw   = false
  format    = "jsonx"
  prefix    = "vault-audit"
}

# Log configuration
log_level = "warn"  # Reduced verbosity for production
log_format = "json"
log_requests_level = "trace"  # Log all requests for security
EOF

    # Update the configuration file
    sed -i.bak '/listener "tcp"/,/^}$/c\
# Enhanced TLS Configuration loaded from separate file\
' "$vault_config"
    
    # Append enhanced config
    cat /tmp/vault-tls-config.hcl >> "$vault_config"
    rm /tmp/vault-tls-config.hcl
    
    log_success "Vault TLS configuration updated"
}

# Update Consul configuration for TLS
update_consul_tls_config() {
    log_info "Updating Consul TLS configuration..."
    
    local consul_config="$PROJECT_ROOT/infrastructure/config/consul.hcl"
    local backup_config="${consul_config}.ssl-backup"
    
    # Backup original config
    cp "$consul_config" "$backup_config"
    
    # Add TLS configuration
    cat >> "$consul_config" << EOF

# Enhanced TLS Configuration
tls {
  defaults {
    verify_incoming = true
    verify_outgoing = true
    verify_server_hostname = true
    
    ca_file   = "/consul/certs/consul-ca.crt"
    cert_file = "/consul/certs/consul.crt"
    key_file  = "/consul/certs/consul.key"
    
    # TLS 1.3 minimum
    tls_min_version = "TLSv1_3"
    
    # Strong cipher suites
    cipher_suites = [
      "TLS_AES_256_GCM_SHA384",
      "TLS_CHACHA20_POLY1305_SHA256",
      "TLS_AES_128_GCM_SHA256"
    ]
  }
  
  https {
    verify_incoming = true
    ca_file   = "/consul/certs/consul-ca.crt"
    cert_file = "/consul/certs/consul.crt"
    key_file  = "/consul/certs/consul.key"
  }
}

# Enhanced ports configuration
ports {
  grpc_tls = 8503
  https    = 8501
  http     = -1  # Disable HTTP
}

# Auto-encrypt for agents
auto_encrypt {
  allow_tls = true
}
EOF

    log_success "Consul TLS configuration updated"
}

# Update Nomad configuration for TLS
update_nomad_tls_config() {
    log_info "Updating Nomad TLS configuration..."
    
    local nomad_config="$PROJECT_ROOT/infrastructure/config/nomad.hcl"
    local backup_config="${nomad_config}.ssl-backup"
    
    # Backup original config
    cp "$nomad_config" "$backup_config"
    
    # Add TLS configuration
    cat >> "$nomad_config" << EOF

# Enhanced TLS Configuration
tls {
  http = true
  rpc  = true
  
  ca_file   = "/nomad/certs/nomad-ca.crt"
  cert_file = "/nomad/certs/nomad.crt"
  key_file  = "/nomad/certs/nomad.key"
  
  verify_server_hostname = true
  verify_https_client    = true
  
  # TLS 1.3 minimum
  tls_min_version = "tls13"
  
  # Strong cipher suites
  tls_cipher_suites = "TLS_AES_256_GCM_SHA384,TLS_CHACHA20_POLY1305_SHA256"
  
  # Prefer server cipher suites
  tls_prefer_server_cipher_suites = true
}

# Enhanced ports configuration
ports {
  http = 4646
  rpc  = 4647
  serf = 4648
}
EOF

    log_success "Nomad TLS configuration updated"
}

# Create certificate rotation automation
create_certificate_rotation() {
    log_info "Creating certificate rotation automation..."
    
    mkdir -p "$PROJECT_ROOT/automation/ssl-scripts"
    
    # Certificate rotation script
    cat > "$PROJECT_ROOT/automation/ssl-scripts/rotate-certificates.sh" << 'EOF'
#!/usr/bin/env bash
# Certificate Rotation Automation
# Automatically rotates SSL certificates before expiration

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-https://vault.cloudya.net:8200}"
DOMAIN="${DOMAIN:-cloudya.net}"
CERT_DIR="/opt/cloudya-infrastructure/automation/ssl-certs"
LOG_FILE="/var/log/cloudya-security/cert-rotation.log"

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE" >&2
}

# Check certificate expiration
check_cert_expiration() {
    local cert_file="$1"
    local service_name="$2"
    local warning_days="${3:-7}"  # Default 7 days warning
    
    if [[ ! -f "$cert_file" ]]; then
        log_error "Certificate file not found: $cert_file"
        return 1
    fi
    
    local exp_date=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
    local exp_timestamp=$(date -d "$exp_date" +%s)
    local current_timestamp=$(date +%s)
    local days_until_expiry=$(( (exp_timestamp - current_timestamp) / 86400 ))
    
    log_info "Certificate for $service_name expires in $days_until_expiry days"
    
    if [[ $days_until_expiry -le $warning_days ]]; then
        log_info "Certificate for $service_name needs rotation"
        return 0  # Needs rotation
    else
        return 1  # No rotation needed
    fi
}

# Rotate service certificate
rotate_service_cert() {
    local service="$1"
    local common_name="$2"
    local alt_names="$3"
    local ip_sans="$4"
    
    log_info "Rotating certificate for $service..."
    
    # Generate new certificate
    vault write -format=json pki_int/issue/cloudya-server \
        common_name="$common_name" \
        alt_names="$alt_names" \
        ip_sans="$ip_sans" \
        ttl="720h" > "/tmp/${service}-cert-new.json"
    
    # Backup old certificate
    cp "$CERT_DIR/services/${service}.crt" "$CERT_DIR/services/${service}.crt.old"
    cp "$CERT_DIR/services/${service}.key" "$CERT_DIR/services/${service}.key.old"
    
    # Install new certificate
    jq -r '.data.certificate' "/tmp/${service}-cert-new.json" > "$CERT_DIR/services/${service}.crt"
    jq -r '.data.private_key' "/tmp/${service}-cert-new.json" > "$CERT_DIR/services/${service}.key"
    jq -r '.data.ca_chain[]' "/tmp/${service}-cert-new.json" > "$CERT_DIR/services/${service}-ca.crt"
    
    # Set permissions
    chmod 600 "$CERT_DIR/services/${service}.key"
    chmod 644 "$CERT_DIR/services/${service}.crt"
    
    # Restart service
    docker-compose -f /opt/cloudya-infrastructure/docker-compose.production.yml restart "$service"
    
    # Cleanup
    rm "/tmp/${service}-cert-new.json"
    
    log_success "Certificate rotated for $service"
}

# Main rotation logic
main() {
    log_info "Starting certificate rotation check..."
    
    # Check and rotate Vault certificate
    if check_cert_expiration "$CERT_DIR/services/vault.crt" "vault"; then
        rotate_service_cert "vault" "vault.$DOMAIN" "vault,localhost" "127.0.0.1,172.25.0.20"
    fi
    
    # Check and rotate Consul certificate
    if check_cert_expiration "$CERT_DIR/services/consul.crt" "consul"; then
        rotate_service_cert "consul" "consul.$DOMAIN" "consul,localhost" "127.0.0.1,172.25.0.10"
    fi
    
    # Check and rotate Nomad certificate
    if check_cert_expiration "$CERT_DIR/services/nomad.crt" "nomad"; then
        rotate_service_cert "nomad" "nomad.$DOMAIN" "nomad,localhost" "127.0.0.1,172.25.0.30"
    fi
    
    # Check and rotate Traefik certificate
    if check_cert_expiration "$CERT_DIR/services/traefik.crt" "traefik"; then
        rotate_service_cert "traefik" "traefik.$DOMAIN" "traefik,localhost" "127.0.0.1"
    fi
    
    log_info "Certificate rotation check completed"
}

main "$@"
EOF

    chmod +x "$PROJECT_ROOT/automation/ssl-scripts/rotate-certificates.sh"
    
    # Certificate monitoring script
    cat > "$PROJECT_ROOT/automation/ssl-scripts/monitor-certificates.sh" << 'EOF'
#!/usr/bin/env bash
# Certificate Monitoring Script
# Monitors certificate health and sends alerts

set -euo pipefail

CERT_DIR="/opt/cloudya-infrastructure/automation/ssl-certs"
ALERT_EMAIL="${ALERT_EMAIL:-admin@cloudya.net}"
LOG_FILE="/var/log/cloudya-security/cert-monitoring.log"

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE" >&2
}

# Send alert email
send_alert() {
    local subject="$1"
    local message="$2"
    
    if command -v mail >/dev/null 2>&1; then
        echo "$message" | mail -s "$subject" "$ALERT_EMAIL"
        log_info "Alert sent to $ALERT_EMAIL"
    else
        log_error "Mail command not available, cannot send alert"
    fi
}

# Check certificate health
check_certificate_health() {
    local cert_file="$1"
    local service_name="$2"
    
    if [[ ! -f "$cert_file" ]]; then
        log_error "Certificate file missing: $cert_file"
        send_alert "Certificate Missing - $service_name" "Certificate file missing: $cert_file"
        return 1
    fi
    
    # Check certificate validity
    if ! openssl x509 -in "$cert_file" -noout -checkend 604800; then  # 7 days
        local exp_date=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
        log_error "Certificate expiring soon: $service_name ($exp_date)"
        send_alert "Certificate Expiring - $service_name" "Certificate for $service_name expires on $exp_date"
        return 1
    fi
    
    log_info "Certificate healthy: $service_name"
    return 0
}

# Main monitoring
main() {
    log_info "Starting certificate health monitoring..."
    
    local issues=0
    
    # Check all service certificates
    for service in vault consul nomad traefik; do
        if ! check_certificate_health "$CERT_DIR/services/${service}.crt" "$service"; then
            ((issues++))
        fi
    done
    
    if [[ $issues -eq 0 ]]; then
        log_info "All certificates are healthy"
    else
        log_error "$issues certificate issues found"
        send_alert "Certificate Health Issues" "$issues certificates have issues. Check logs for details."
    fi
    
    log_info "Certificate monitoring completed"
}

main "$@"
EOF

    chmod +x "$PROJECT_ROOT/automation/ssl-scripts/monitor-certificates.sh"
    
    log_success "Certificate rotation and monitoring scripts created"
}

# Create systemd timer for certificate rotation
create_certificate_timer() {
    log_info "Creating systemd timer for certificate rotation..."
    
    # Certificate rotation service
    cat > /tmp/cert-rotation.service << 'EOF'
[Unit]
Description=CloudYa Certificate Rotation
After=vault.service

[Service]
Type=oneshot
User=root
ExecStart=/opt/cloudya-infrastructure/automation/ssl-scripts/rotate-certificates.sh
StandardOutput=journal
StandardError=journal
EOF

    # Certificate rotation timer
    cat > /tmp/cert-rotation.timer << 'EOF'
[Unit]
Description=Run CloudYa Certificate Rotation Daily
Requires=cert-rotation.service

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=3600

[Install]
WantedBy=timers.target
EOF

    # Install service and timer
    sudo mv /tmp/cert-rotation.service /etc/systemd/system/
    sudo mv /tmp/cert-rotation.timer /etc/systemd/system/
    
    sudo systemctl daemon-reload
    sudo systemctl enable cert-rotation.timer
    sudo systemctl start cert-rotation.timer
    
    log_success "Certificate rotation timer configured"
}

# Main execution
main() {
    log_info "Starting SSL certificate automation..."
    
    # Create certificate directories
    mkdir -p "$PROJECT_ROOT/automation/ssl-certs/services"
    mkdir -p "$PROJECT_ROOT/automation/ssl-certs/clients"
    
    # Setup PKI infrastructure
    setup_pki_infrastructure
    setup_intermediate_ca
    create_certificate_roles
    
    # Generate certificates
    generate_service_certificates
    generate_client_certificates
    
    # Update service configurations
    update_vault_tls_config
    update_consul_tls_config
    update_nomad_tls_config
    
    # Create automation scripts
    create_certificate_rotation
    create_certificate_timer
    
    log_success "SSL certificate automation completed successfully!"
    log_info "Certificates generated and stored in automation/ssl-certs/"
    log_info "Service configurations updated for enhanced TLS security"
    log_info "Certificate rotation automation configured"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi