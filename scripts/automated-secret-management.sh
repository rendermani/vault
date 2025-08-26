#!/bin/bash
# Automated Secret Management Script
# Integrates with Vault for secure credential handling
# Replaces hardcoded credentials with Vault-managed secrets

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VAULT_ADDR="${VAULT_ADDR:-https://vault.cloudya.net:8200}"
VAULT_NAMESPACE="${VAULT_NAMESPACE:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[SECRET-MGR]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Vault client wrapper with error handling
vault_cmd() {
    if ! command -v vault >/dev/null 2>&1; then
        log_error "Vault CLI not found. Please install Vault client."
        exit 1
    fi
    
    if ! vault status >/dev/null 2>&1; then
        log_error "Cannot connect to Vault at $VAULT_ADDR"
        log_info "Please ensure Vault is running and accessible"
        exit 1
    fi
    
    vault "$@"
}

# Generate secure random password
generate_secure_password() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
}

# Generate bcrypt hash for basic auth
generate_bcrypt_hash() {
    local password="$1"
    # Use htpasswd if available, otherwise use openssl
    if command -v htpasswd >/dev/null 2>&1; then
        htpasswd -nbB "" "$password" | cut -d: -f2
    else
        # Fallback to a simple hash (not bcrypt, but better than plaintext)
        echo "$password" | openssl passwd -1 -stdin
    fi
}

# Initialize Vault secret engines
init_vault_engines() {
    log_info "Initializing Vault secret engines..."
    
    # Enable KV v2 secret engine for application secrets
    if ! vault_cmd secrets list | grep -q "cloudya-secrets/"; then
        vault_cmd secrets enable -path=cloudya-secrets kv-v2
        log_success "Enabled KV v2 secret engine at cloudya-secrets/"
    fi
    
    # Enable database secret engine for dynamic credentials
    if ! vault_cmd secrets list | grep -q "database/"; then
        vault_cmd secrets enable database
        log_success "Enabled database secret engine"
    fi
    
    # Enable PKI secret engine for certificate management
    if ! vault_cmd secrets list | grep -q "pki/"; then
        vault_cmd secrets enable pki
        vault_cmd secrets tune -max-lease-ttl=87600h pki
        log_success "Enabled PKI secret engine"
    fi
    
    # Enable transit secret engine for encryption as a service
    if ! vault_cmd secrets list | grep -q "transit/"; then
        vault_cmd secrets enable transit
        log_success "Enabled transit secret engine"
    fi
}

# Create Vault policies for different roles
create_vault_policies() {
    log_info "Creating Vault policies..."
    
    # Application policy for reading secrets
    cat > /tmp/cloudya-app-policy.hcl <<EOF
# Application policy for CloudYa services
path "cloudya-secrets/data/traefik/*" {
  capabilities = ["read"]
}

path "cloudya-secrets/data/grafana/*" {
  capabilities = ["read"]
}

path "cloudya-secrets/data/consul/*" {
  capabilities = ["read"]
}

path "cloudya-secrets/data/nomad/*" {
  capabilities = ["read"]
}

path "database/creds/cloudya-db" {
  capabilities = ["read"]
}

path "transit/encrypt/cloudya-key" {
  capabilities = ["update"]
}

path "transit/decrypt/cloudya-key" {
  capabilities = ["update"]
}

path "pki/issue/cloudya-role" {
  capabilities = ["update"]
}
EOF
    
    vault_cmd policy write cloudya-app /tmp/cloudya-app-policy.hcl
    rm -f /tmp/cloudya-app-policy.hcl
    log_success "Created application policy"
    
    # Admin policy for secret management
    cat > /tmp/cloudya-admin-policy.hcl <<EOF
# Admin policy for CloudYa secret management
path "cloudya-secrets/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "database/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "pki/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "transit/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "auth/approle/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
    
    vault_cmd policy write cloudya-admin /tmp/cloudya-admin-policy.hcl
    rm -f /tmp/cloudya-admin-policy.hcl
    log_success "Created admin policy"
}

# Setup AppRole authentication
setup_approle_auth() {
    log_info "Setting up AppRole authentication..."
    
    # Enable AppRole auth method
    if ! vault_cmd auth list | grep -q "approle/"; then
        vault_cmd auth enable approle
        log_success "Enabled AppRole authentication"
    fi
    
    # Create application role
    vault_cmd write auth/approle/role/cloudya-app \
        token_policies="cloudya-app" \
        token_ttl=1h \
        token_max_ttl=4h \
        bind_secret_id=true
    
    log_success "Created CloudYa application role"
    
    # Get role ID (this can be stored in configuration)
    ROLE_ID=$(vault_cmd read -field=role_id auth/approle/role/cloudya-app/role-id)
    log_info "Application Role ID: $ROLE_ID"
    
    # Generate secret ID (this should be securely delivered to applications)
    SECRET_ID=$(vault_cmd write -field=secret_id auth/approle/role/cloudya-app/secret-id)
    log_warning "Application Secret ID generated (store securely): $SECRET_ID"
    
    # Store credentials in a secure file
    cat > "$PROJECT_ROOT/.vault-approle" <<EOF
# Vault AppRole Credentials for CloudYa
# Keep this file secure and restrict access
VAULT_ROLE_ID="$ROLE_ID"
VAULT_SECRET_ID="$SECRET_ID"
EOF
    chmod 600 "$PROJECT_ROOT/.vault-approle"
    log_success "Stored AppRole credentials in .vault-approle"
}

# Store service credentials in Vault
store_service_credentials() {
    log_info "Storing service credentials in Vault..."
    
    # Generate new passwords
    local traefik_admin_password=$(generate_secure_password 24)
    local grafana_admin_password=$(generate_secure_password 24)
    local consul_encrypt_key=$(vault_cmd write -field=key transit/datakey/plaintext/cloudya-key | base64 -w 0)
    
    # Generate bcrypt hashes for basic auth
    local traefik_admin_hash=$(generate_bcrypt_hash "$traefik_admin_password")
    
    # Store Traefik credentials
    vault_cmd kv put cloudya-secrets/traefik/auth \
        admin_username="admin" \
        admin_password="$traefik_admin_password" \
        admin_hash="$traefik_admin_hash"
    
    # Store Grafana credentials
    vault_cmd kv put cloudya-secrets/grafana/auth \
        admin_username="admin" \
        admin_password="$grafana_admin_password"
    
    # Store Consul encryption key
    vault_cmd kv put cloudya-secrets/consul/config \
        encrypt_key="$consul_encrypt_key"
    
    # Store database credentials template
    vault_cmd kv put cloudya-secrets/database/config \
        host="localhost" \
        port="5432" \
        database="cloudya" \
        ssl_mode="require"
    
    log_success "Stored service credentials in Vault"
    log_info "Traefik admin password: $traefik_admin_password"
    log_info "Grafana admin password: $grafana_admin_password"
}

# Generate PKI certificates
setup_pki_certificates() {
    log_info "Setting up PKI certificates..."
    
    # Generate root CA
    vault_cmd write pki/root/generate/internal \
        common_name="CloudYa Internal CA" \
        ttl=87600h
    
    # Configure certificate URLs
    vault_cmd write pki/config/urls \
        issuing_certificates="$VAULT_ADDR/v1/pki/ca" \
        crl_distribution_points="$VAULT_ADDR/v1/pki/crl"
    
    # Create role for CloudYa services
    vault_cmd write pki/roles/cloudya-role \
        allowed_domains="cloudya.net,*.cloudya.net,localhost" \
        allow_subdomains=true \
        allow_localhost=true \
        max_ttl=720h
    
    log_success "PKI certificates configured"
}

# Create Vault agent configuration
create_vault_agent_config() {
    log_info "Creating Vault agent configuration..."
    
    mkdir -p "$PROJECT_ROOT/vault/agent"
    
    cat > "$PROJECT_ROOT/vault/agent/vault-agent.hcl" <<EOF
# Vault Agent Configuration for CloudYa
pid_file = "/var/run/vault/vault-agent.pid"
exit_after_auth = false

vault {
  address = "$VAULT_ADDR"
}

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path = "/etc/vault/role-id"
      secret_id_file_path = "/etc/vault/secret-id"
    }
  }

  sink "file" {
    config = {
      path = "/var/run/vault/agent-token"
      mode = 0644
    }
  }
}

# Template for Docker Compose environment
template {
  source = "/etc/vault/templates/docker-compose.env.tpl"
  destination = "/opt/cloudya/.env"
  perms = 0600
  command = "docker-compose up -d"
  command_timeout = "60s"
}

# Template for Traefik basic auth
template {
  source = "/etc/vault/templates/traefik-auth.tpl"
  destination = "/opt/cloudya/traefik/auth/users.htpasswd"
  perms = 0644
  command = "docker-compose restart traefik"
  command_timeout = "30s"
}

# Template for Grafana configuration
template {
  source = "/etc/vault/templates/grafana.env.tpl"
  destination = "/opt/cloudya/grafana/grafana.env"
  perms = 0600
  command = "docker-compose restart grafana"
  command_timeout = "30s"
}
EOF
    
    # Create template directory
    mkdir -p "$PROJECT_ROOT/vault/agent/templates"
    
    # Create Docker Compose environment template
    cat > "$PROJECT_ROOT/vault/agent/templates/docker-compose.env.tpl" <<'EOF'
{{- with secret "cloudya-secrets/data/traefik/auth" }}
TRAEFIK_ADMIN_USER={{ .Data.data.admin_username }}
TRAEFIK_ADMIN_PASSWORD={{ .Data.data.admin_password }}
TRAEFIK_ADMIN_HASH={{ .Data.data.admin_hash }}
{{- end }}

{{- with secret "cloudya-secrets/data/grafana/auth" }}
GRAFANA_ADMIN_USER={{ .Data.data.admin_username }}
GRAFANA_ADMIN_PASSWORD={{ .Data.data.admin_password }}
{{- end }}

{{- with secret "cloudya-secrets/data/consul/config" }}
CONSUL_ENCRYPT_KEY={{ .Data.data.encrypt_key }}
{{- end }}

{{- with secret "cloudya-secrets/data/database/config" }}
DB_HOST={{ .Data.data.host }}
DB_PORT={{ .Data.data.port }}
DB_NAME={{ .Data.data.database }}
DB_SSL_MODE={{ .Data.data.ssl_mode }}
{{- end }}

# Generated by Vault Agent
# Do not edit manually
VAULT_MANAGED=true
GENERATED_AT={{ now | date "2006-01-02T15:04:05Z07:00" }}
EOF
    
    # Create Traefik auth template
    cat > "$PROJECT_ROOT/vault/agent/templates/traefik-auth.tpl" <<'EOF'
{{- with secret "cloudya-secrets/data/traefik/auth" }}
{{ .Data.data.admin_username }}:{{ .Data.data.admin_hash }}
{{- end }}
EOF
    
    # Create Grafana environment template
    cat > "$PROJECT_ROOT/vault/agent/templates/grafana.env.tpl" <<'EOF'
{{- with secret "cloudya-secrets/data/grafana/auth" }}
GF_SECURITY_ADMIN_USER={{ .Data.data.admin_username }}
GF_SECURITY_ADMIN_PASSWORD={{ .Data.data.admin_password }}
{{- end }}
GF_SECURITY_SECRET_KEY={{ uuidv4 }}
GF_SECURITY_DISABLE_GRAVATAR=true
GF_USERS_ALLOW_SIGN_UP=false
GF_USERS_ALLOW_ORG_CREATE=false
EOF
    
    log_success "Created Vault agent configuration"
}

# Generate systemd service for Vault Agent
create_vault_agent_service() {
    log_info "Creating Vault Agent systemd service..."
    
    cat > /tmp/vault-agent.service <<EOF
[Unit]
Description=Vault Agent
Documentation=https://developer.hashicorp.com/vault/docs/agent
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault/agent/vault-agent.hcl

[Service]
Type=notify
User=vault
Group=vault
ExecStart=/usr/local/bin/vault agent -config=/etc/vault/agent/vault-agent.hcl
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
    
    log_warning "Systemd service file created at /tmp/vault-agent.service"
    log_info "To install: sudo mv /tmp/vault-agent.service /etc/systemd/system/"
    log_info "Then run: sudo systemctl daemon-reload && sudo systemctl enable vault-agent"
}

# Backup existing configuration
backup_existing_config() {
    log_info "Backing up existing configuration..."
    
    local backup_dir="$PROJECT_ROOT/backups/pre-vault-integration-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup Docker Compose files
    find "$PROJECT_ROOT" -name "docker-compose*.yml" -exec cp {} "$backup_dir/" \;
    
    # Backup configuration files
    if [ -d "$PROJECT_ROOT/config" ]; then
        cp -r "$PROJECT_ROOT/config" "$backup_dir/"
    fi
    
    log_success "Configuration backed up to: $backup_dir"
}

# Create updated Docker Compose with Vault integration
create_updated_docker_compose() {
    log_info "Creating Vault-integrated Docker Compose configuration..."
    
    cat > "$PROJECT_ROOT/docker-compose.vault-integrated.yml" <<'EOF'
version: '3.8'

networks:
  cloudya:
    external: false
    driver: bridge
    ipam:
      config:
        - subnet: 172.25.0.0/16

volumes:
  vault_data:
    driver: local
  consul_data:
    driver: local
  nomad_data:
    driver: local
  traefik_data:
    driver: local

services:
  vault-agent:
    image: hashicorp/vault:1.17.6
    container_name: cloudya-vault-agent
    restart: unless-stopped
    networks:
      - cloudya
    volumes:
      - ./vault/agent:/etc/vault/agent:ro
      - /var/run/vault:/var/run/vault
      - .:/opt/cloudya
    environment:
      - VAULT_ADDR=${VAULT_ADDR}
    command: ["vault", "agent", "-config=/etc/vault/agent/vault-agent.hcl"]
    depends_on:
      - vault

  consul:
    image: hashicorp/consul:1.19.2
    container_name: cloudya-consul
    restart: unless-stopped
    networks:
      cloudya:
        ipv4_address: 172.25.0.10
    ports:
      - "8500:8500"
      - "8600:8600/udp"
    volumes:
      - consul_data:/consul/data
      - ./config/consul.hcl:/consul/config/consul.hcl:ro
    environment:
      - CONSUL_BIND_INTERFACE=eth0
      - CONSUL_CLIENT_INTERFACE=eth0
      - CONSUL_ENCRYPT_KEY_FILE=/run/secrets/consul_encrypt_key
    secrets:
      - consul_encrypt_key
    healthcheck:
      test: ["CMD", "consul", "members"]
      interval: 30s
      timeout: 10s
      retries: 3

  vault:
    image: hashicorp/vault:1.17.6
    container_name: cloudya-vault
    restart: unless-stopped
    networks:
      cloudya:
        ipv4_address: 172.25.0.20
    ports:
      - "8200:8200"
    volumes:
      - vault_data:/vault/data
      - ./config/vault.hcl:/vault/config/vault.hcl:ro
      - ./certs:/vault/certs:ro
    cap_add:
      - IPC_LOCK
    environment:
      - VAULT_ADDR=https://0.0.0.0:8200
      - VAULT_API_ADDR=https://vault.cloudya.net:8200
    depends_on:
      consul:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "vault", "status"]
      interval: 30s
      timeout: 10s
      retries: 5

  traefik:
    image: traefik:v3.2.3
    container_name: cloudya-traefik
    restart: unless-stopped
    networks:
      - cloudya
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"
    volumes:
      - ./config/traefik-improved.yml:/etc/traefik/traefik.yml:ro
      - ./config/dynamic:/etc/traefik/dynamic:ro
      - traefik_data:/letsencrypt
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik/auth:/etc/traefik/auth:ro
    environment:
      - TRAEFIK_AUTH_FILE=/etc/traefik/auth/users.htpasswd
    depends_on:
      - vault-agent
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8080/ping"]
      interval: 30s
      timeout: 10s
      retries: 3

  grafana:
    image: grafana/grafana:11.2.2
    container_name: cloudya-grafana
    restart: unless-stopped
    networks:
      cloudya:
        ipv4_address: 172.25.0.50
    ports:
      - "3000:3000"
    volumes:
      - /opt/cloudya-data/monitoring/grafana:/var/lib/grafana
    env_file:
      - ./grafana/grafana.env
    depends_on:
      - vault-agent

secrets:
  consul_encrypt_key:
    external: true
EOF
    
    log_success "Created Vault-integrated Docker Compose configuration"
}

# Main execution function
main() {
    log_info "Starting automated secret management setup..."
    
    # Check prerequisites
    if ! command -v vault >/dev/null 2>&1; then
        log_error "Vault CLI not found. Please install Vault client first."
        exit 1
    fi
    
    if ! command -v openssl >/dev/null 2>&1; then
        log_error "OpenSSL not found. Please install OpenSSL."
        exit 1
    fi
    
    # Create backups
    backup_existing_config
    
    # Initialize Vault
    init_vault_engines
    create_vault_policies
    setup_approle_auth
    store_service_credentials
    setup_pki_certificates
    
    # Create configuration files
    create_vault_agent_config
    create_vault_agent_service
    create_updated_docker_compose
    
    log_success "Automated secret management setup completed!"
    echo ""
    log_info "Next steps:"
    log_info "1. Review generated configurations"
    log_info "2. Install Vault Agent systemd service"
    log_info "3. Test Vault integration"
    log_info "4. Replace original docker-compose.yml"
    log_info "5. Restart services with new configuration"
    echo ""
    log_warning "Important: Store .vault-approle file securely!"
    log_warning "Credentials have been stored in Vault at cloudya-secrets/"
}

# Handle command line arguments
case "${1:-setup}" in
    setup)
        main
        ;;
    init-engines)
        init_vault_engines
        ;;
    create-policies)
        create_vault_policies
        ;;
    store-secrets)
        store_service_credentials
        ;;
    setup-pki)
        setup_pki_certificates
        ;;
    create-agent)
        create_vault_agent_config
        create_vault_agent_service
        ;;
    test)
        log_info "Testing Vault connectivity..."
        vault_cmd status
        log_success "Vault connection successful"
        ;;
    *)
        echo "Usage: $0 {setup|init-engines|create-policies|store-secrets|setup-pki|create-agent|test}"
        echo ""
        echo "Commands:"
        echo "  setup         - Complete automated secret management setup"
        echo "  init-engines  - Initialize Vault secret engines only"
        echo "  create-policies - Create Vault policies only"
        echo "  store-secrets - Store service credentials only"
        echo "  setup-pki     - Setup PKI certificates only"
        echo "  create-agent  - Create Vault agent configuration only"
        echo "  test          - Test Vault connectivity"
        exit 1
        ;;
esac