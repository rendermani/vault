#!/usr/bin/env bash
# Secrets Migration Automation
# Migrates all hardcoded credentials to Vault and updates configurations
#
# This script addresses CRITICAL findings:
# - Hardcoded Basic Auth Credentials (docker-compose.production.yml)
# - Default Grafana Admin Password
# - Manual Vault Unsealing

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
    echo -e "${BLUE}[SECRETS-MIGRATION]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_DIR/secrets-migration.log"
}

log_success() {
    echo -e "${GREEN}[SECRETS-MIGRATION]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_DIR/secrets-migration.log"
}

log_error() {
    echo -e "${RED}[SECRETS-MIGRATION]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_DIR/secrets-migration.log" >&2
}

# Generate secure password
generate_secure_password() {
    local length=${1:-32}
    openssl rand -base64 $((length * 3 / 4)) | tr -d "=+/" | cut -c1-${length}
}

# Generate bcrypt hash
generate_bcrypt_hash() {
    local password="$1"
    python3 -c "
import bcrypt
import sys
password = '$password'.encode('utf-8')
hashed = bcrypt.hashpw(password, bcrypt.gensalt(rounds=12))
# Docker-compose requires $$ escaping
print(hashed.decode('utf-8').replace('$', '$$'))
"
}

# Enable Vault KV engine
enable_kv_engine() {
    log_info "Enabling KV secrets engine in Vault..."
    
    if ! vault secrets list | grep -q "secret/"; then
        vault secrets enable -path=secret kv-v2
        log_success "KV secrets engine enabled"
    else
        log_info "KV secrets engine already enabled"
    fi
}

# Create Vault policies for secret access
create_vault_policies() {
    log_info "Creating Vault policies for secret access..."
    
    # Traefik policy
    cat > /tmp/traefik-secrets-policy.hcl << EOF
# Traefik secrets policy
path "secret/data/cloudya/traefik/*" {
  capabilities = ["read"]
}

path "secret/metadata/cloudya/traefik/*" {
  capabilities = ["list", "read"]
}

# PKI for certificates
path "pki/issue/cloudya-dot-net" {
  capabilities = ["create", "update"]
}

path "pki/cert/ca" {
  capabilities = ["read"]
}
EOF

    vault policy write traefik-secrets /tmp/traefik-secrets-policy.hcl
    
    # Grafana policy
    cat > /tmp/grafana-secrets-policy.hcl << EOF
# Grafana secrets policy
path "secret/data/cloudya/grafana/*" {
  capabilities = ["read"]
}

path "secret/metadata/cloudya/grafana/*" {
  capabilities = ["list", "read"]
}
EOF

    vault policy write grafana-secrets /tmp/grafana-secrets-policy.hcl
    
    # Prometheus policy
    cat > /tmp/prometheus-secrets-policy.hcl << EOF
# Prometheus secrets policy
path "secret/data/cloudya/prometheus/*" {
  capabilities = ["read"]
}

path "secret/metadata/cloudya/prometheus/*" {
  capabilities = ["list", "read"]
}
EOF

    vault policy write prometheus-secrets /tmp/prometheus-secrets-policy.hcl
    
    # Consul policy
    cat > /tmp/consul-secrets-policy.hcl << EOF
# Consul secrets policy
path "secret/data/cloudya/consul/*" {
  capabilities = ["read"]
}

path "secret/metadata/cloudya/consul/*" {
  capabilities = ["list", "read"]
}
EOF

    vault policy write consul-secrets /tmp/consul-secrets-policy.hcl
    
    # Cleanup
    rm -f /tmp/*-secrets-policy.hcl
    
    log_success "Vault policies created"
}

# Generate and store secure credentials
generate_and_store_credentials() {
    log_info "Generating and storing secure credentials in Vault..."
    
    # Generate secure passwords
    local traefik_admin_password=$(generate_secure_password 24)
    local grafana_admin_password=$(generate_secure_password 24)
    local prometheus_admin_password=$(generate_secure_password 24)
    local consul_admin_password=$(generate_secure_password 24)
    
    # Generate bcrypt hashes for basic auth
    local traefik_admin_hash=$(generate_bcrypt_hash "$traefik_admin_password")
    local prometheus_admin_hash=$(generate_bcrypt_hash "$prometheus_admin_password")
    local consul_admin_hash=$(generate_bcrypt_hash "$consul_admin_password")
    
    # Store Traefik credentials
    vault kv put secret/cloudya/traefik/admin \
        username="admin" \
        password="$traefik_admin_password" \
        bcrypt_hash="$traefik_admin_hash"
    
    # Store Grafana credentials
    vault kv put secret/cloudya/grafana/admin \
        username="admin" \
        password="$grafana_admin_password"
    
    # Store Prometheus credentials
    vault kv put secret/cloudya/prometheus/admin \
        username="admin" \
        password="$prometheus_admin_password" \
        bcrypt_hash="$prometheus_admin_hash"
    
    # Store Consul credentials
    vault kv put secret/cloudya/consul/admin \
        username="admin" \
        password="$consul_admin_password" \
        bcrypt_hash="$consul_admin_hash"
    
    # Store database credentials
    vault kv put secret/cloudya/database/postgres \
        username="postgres" \
        password="$(generate_secure_password 32)" \
        root_password="$(generate_secure_password 32)"
    
    # Store ACME email for Let's Encrypt
    vault kv put secret/cloudya/certificates/acme \
        email="admin@cloudya.net"
    
    log_success "Secure credentials generated and stored in Vault"
    
    # Log credential info (without passwords)
    log_info "Credential storage locations:"
    log_info "  - Traefik admin: secret/cloudya/traefik/admin"
    log_info "  - Grafana admin: secret/cloudya/grafana/admin"
    log_info "  - Prometheus admin: secret/cloudya/prometheus/admin"
    log_info "  - Consul admin: secret/cloudya/consul/admin"
    log_info "  - Database: secret/cloudya/database/postgres"
}

# Create Vault Agent templates
create_vault_agent_templates() {
    log_info "Creating Vault Agent templates for secret injection..."
    
    mkdir -p "$PROJECT_ROOT/automation/templates"
    
    # Traefik basic auth template
    cat > "$PROJECT_ROOT/automation/templates/traefik-auth.tpl" << 'EOF'
{{ with secret "secret/cloudya/traefik/admin" -}}
{{ .Data.data.username }}:{{ .Data.data.bcrypt_hash }}
{{- end }}
EOF

    # Grafana environment template
    cat > "$PROJECT_ROOT/automation/templates/grafana-env.tpl" << 'EOF'
{{ with secret "secret/cloudya/grafana/admin" -}}
GF_SECURITY_ADMIN_USER={{ .Data.data.username }}
GF_SECURITY_ADMIN_PASSWORD={{ .Data.data.password }}
{{- end }}
EOF

    # Prometheus basic auth template
    cat > "$PROJECT_ROOT/automation/templates/prometheus-auth.tpl" << 'EOF'
{{ with secret "secret/cloudya/prometheus/admin" -}}
{{ .Data.data.username }}:{{ .Data.data.bcrypt_hash }}
{{- end }}
EOF

    # Consul basic auth template
    cat > "$PROJECT_ROOT/automation/templates/consul-auth.tpl" << 'EOF'
{{ with secret "secret/cloudya/consul/admin" -}}
{{ .Data.data.username }}:{{ .Data.data.bcrypt_hash }}
{{- end }}
EOF

    # Docker-compose template
    cat > "$PROJECT_ROOT/automation/templates/docker-compose-production.yml.tpl" << 'EOF'
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
    driver_opts:
      type: none
      device: /opt/cloudya-data/vault
      o: bind
  consul_data:
    driver: local
    driver_opts:
      type: none
      device: /opt/cloudya-data/consul
      o: bind
  nomad_data:
    driver: local
    driver_opts:
      type: none
      device: /opt/cloudya-data/nomad
      o: bind
  traefik_data:
    driver: local
    driver_opts:
      type: none
      device: /opt/cloudya-data/traefik
      o: bind

services:
  consul:
    image: hashicorp/consul:1.19.2
    container_name: cloudya-consul
    restart: unless-stopped
    networks:
      cloudya:
        ipv4_address: 172.25.0.10
    ports:
      - "127.0.0.1:8500:8500"
      - "127.0.0.1:8600:8600/udp"
    volumes:
      - consul_data:/consul/data
      - /opt/cloudya-infrastructure/config/consul.hcl:/consul/config/consul.hcl:ro
    command: ["consul", "agent", "-config-file=/consul/config/consul.hcl"]
    environment:
      - CONSUL_BIND_INTERFACE=eth0
      - CONSUL_CLIENT_INTERFACE=eth0
    healthcheck:
      test: ["CMD", "consul", "members"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.consul.rule=Host(`consul.cloudya.net`)"
      - "traefik.http.routers.consul.tls=true"
      - "traefik.http.routers.consul.tls.certresolver=letsencrypt"
      - "traefik.http.services.consul.loadbalancer.server.port=8500"
{{ with secret "secret/cloudya/consul/admin" -}}
      - "traefik.http.middlewares.consul-auth.basicauth.users={{ .Data.data.username }}:{{ .Data.data.bcrypt_hash }}"
{{- end }}
      - "traefik.http.routers.consul.middlewares=consul-auth"

  vault:
    image: hashicorp/vault:1.17.6
    container_name: cloudya-vault
    restart: unless-stopped
    networks:
      cloudya:
        ipv4_address: 172.25.0.20
    ports:
      - "127.0.0.1:8200:8200"
    volumes:
      - vault_data:/vault/data
      - /opt/cloudya-infrastructure/vault/config/vault.hcl:/vault/config/vault.hcl:ro
      - /opt/cloudya-infrastructure/certs:/vault/certs:ro
    cap_add:
      - IPC_LOCK
    command: ["vault", "server", "-config=/vault/config/vault.hcl"]
    environment:
      - VAULT_ADDR=https://0.0.0.0:8200
      - VAULT_API_ADDR=https://vault.cloudya.net:8200
    depends_on:
      consul:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "vault", "status", "-address=https://127.0.0.1:8200"]
      interval: 30s
      timeout: 10s
      retries: 5
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.vault.rule=Host(`vault.cloudya.net`)"
      - "traefik.http.routers.vault.tls=true"
      - "traefik.http.routers.vault.tls.certresolver=letsencrypt"
      - "traefik.http.services.vault.loadbalancer.server.port=8200"
      - "traefik.http.services.vault.loadbalancer.server.scheme=https"
      - "traefik.http.middlewares.vault-headers.headers.customrequestheaders.X-Forwarded-Proto=https"
      - "traefik.http.routers.vault.middlewares=vault-headers"

  nomad:
    image: hashicorp/nomad:1.8.4
    container_name: cloudya-nomad
    restart: unless-stopped
    networks:
      cloudya:
        ipv4_address: 172.25.0.30
    ports:
      - "127.0.0.1:4646:4646"
      - "127.0.0.1:4647:4647"
      - "127.0.0.1:4648:4648"
    volumes:
      - nomad_data:/nomad/data
      - /opt/cloudya-infrastructure/nomad/config/nomad.hcl:/nomad/config/nomad.hcl:ro
      - /var/run/docker.sock:/var/run/docker.sock
    command: ["nomad", "agent", "-config=/nomad/config/nomad.hcl"]
    depends_on:
      consul:
        condition: service_healthy
      vault:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "nomad", "status"]
      interval: 30s
      timeout: 10s
      retries: 5
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.nomad.rule=Host(`nomad.cloudya.net`)"
      - "traefik.http.routers.nomad.tls=true"
      - "traefik.http.routers.nomad.tls.certresolver=letsencrypt"
      - "traefik.http.services.nomad.loadbalancer.server.port=4646"

  traefik:
    image: traefik:v3.2.3
    container_name: cloudya-traefik
    restart: unless-stopped
    networks:
      - cloudya
    ports:
      - "80:80"
      - "443:443"
      - "127.0.0.1:8080:8080"
    volumes:
      - /opt/cloudya-infrastructure/traefik/config/traefik.yml:/etc/traefik/traefik.yml:ro
      - /opt/cloudya-infrastructure/traefik/config/dynamic:/etc/traefik/dynamic:ro
      - traefik_data:/letsencrypt
      - /var/run/docker.sock:/var/run/docker.sock:ro
    command:
      - "--configFile=/etc/traefik/traefik.yml"
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8080/ping"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.dashboard.rule=Host(`traefik.cloudya.net`)"
      - "traefik.http.routers.dashboard.tls=true"
      - "traefik.http.routers.dashboard.tls.certresolver=letsencrypt"
      - "traefik.http.routers.dashboard.service=api@internal"
{{ with secret "secret/cloudya/traefik/admin" -}}
      - "traefik.http.middlewares.dashboard-auth.basicauth.users={{ .Data.data.username }}:{{ .Data.data.bcrypt_hash }}"
{{- end }}
      - "traefik.http.routers.dashboard.middlewares=dashboard-auth"

  prometheus:
    image: prom/prometheus:v2.54.1
    container_name: cloudya-prometheus
    restart: unless-stopped
    networks:
      cloudya:
        ipv4_address: 172.25.0.40
    ports:
      - "127.0.0.1:9090:9090"
    volumes:
      - /opt/cloudya-data/monitoring/prometheus:/prometheus
      - /opt/cloudya-infrastructure/monitoring/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
      - '--web.enable-lifecycle'
      - '--web.external-url=https://prometheus.cloudya.net'
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.prometheus.rule=Host(`prometheus.cloudya.net`)"
      - "traefik.http.routers.prometheus.tls=true"
      - "traefik.http.routers.prometheus.tls.certresolver=letsencrypt"
      - "traefik.http.services.prometheus.loadbalancer.server.port=9090"
{{ with secret "secret/cloudya/prometheus/admin" -}}
      - "traefik.http.middlewares.prometheus-auth.basicauth.users={{ .Data.data.username }}:{{ .Data.data.bcrypt_hash }}"
{{- end }}
      - "traefik.http.routers.prometheus.middlewares=prometheus-auth"

  grafana:
    image: grafana/grafana:11.2.2
    container_name: cloudya-grafana
    restart: unless-stopped
    networks:
      cloudya:
        ipv4_address: 172.25.0.50
    ports:
      - "127.0.0.1:3000:3000"
    volumes:
      - /opt/cloudya-data/monitoring/grafana:/var/lib/grafana
    env_file:
      - /opt/cloudya-infrastructure/secrets/grafana.env
    user: "472:472"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.grafana.rule=Host(`grafana.cloudya.net`)"
      - "traefik.http.routers.grafana.tls=true"
      - "traefik.http.routers.grafana.tls.certresolver=letsencrypt"
      - "traefik.http.services.grafana.loadbalancer.server.port=3000"

  vault-agent:
    image: hashicorp/vault:1.17.6
    container_name: cloudya-vault-agent
    restart: unless-stopped
    networks:
      - cloudya
    volumes:
      - /opt/cloudya-infrastructure/vault/agent:/vault/config:ro
      - /opt/cloudya-infrastructure/secrets:/vault/secrets
      - /opt/cloudya-infrastructure/automation/templates:/vault/templates:ro
    command: ["vault", "agent", "-config=/vault/config/agent.hcl"]
    depends_on:
      vault:
        condition: service_healthy
EOF

    log_success "Vault Agent templates created"
}

# Create Vault Agent configuration
create_vault_agent_config() {
    log_info "Creating Vault Agent configuration..."
    
    mkdir -p "$PROJECT_ROOT/infrastructure/vault/agent"
    
    # Create AppRole for Vault Agent
    vault auth enable -path=approle approle 2>/dev/null || log_info "AppRole auth already enabled"
    
    # Create policy for Vault Agent
    cat > /tmp/vault-agent-policy.hcl << EOF
# Vault Agent policy for secret access
path "secret/data/cloudya/*" {
  capabilities = ["read"]
}

path "secret/metadata/cloudya/*" {
  capabilities = ["list", "read"]
}

# Auth token lookup
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF

    vault policy write vault-agent /tmp/vault-agent-policy.hcl
    rm /tmp/vault-agent-policy.hcl
    
    # Create AppRole
    vault write auth/approle/role/vault-agent \
        token_policies="vault-agent" \
        token_ttl=1h \
        token_max_ttl=4h \
        bind_secret_id=true
    
    # Get role ID and secret ID
    local role_id=$(vault read -field=role_id auth/approle/role/vault-agent/role-id)
    local secret_id=$(vault write -field=secret_id auth/approle/role/vault-agent/secret-id)
    
    # Create Vault Agent configuration
    cat > "$PROJECT_ROOT/infrastructure/vault/agent/agent.hcl" << EOF
pid_file = "/tmp/vault-agent.pid"

vault {
  address = "$VAULT_ADDR"
  retry {
    num_retries = 5
  }
}

auto_auth {
  method "approle" {
    config = {
      role_id_file_path   = "/vault/config/role_id"
      secret_id_file_path = "/vault/config/secret_id"
    }
  }

  sink "file" {
    config = {
      path = "/vault/secrets/token"
    }
  }
}

template {
  source      = "/vault/templates/traefik-auth.tpl"
  destination = "/vault/secrets/traefik-auth"
  perms       = 0600
  command     = "docker-compose -f /opt/cloudya-infrastructure/docker-compose.production.yml restart traefik"
}

template {
  source      = "/vault/templates/grafana-env.tpl"
  destination = "/vault/secrets/grafana.env"
  perms       = 0600
  command     = "docker-compose -f /opt/cloudya-infrastructure/docker-compose.production.yml restart grafana"
}

template {
  source      = "/vault/templates/prometheus-auth.tpl"
  destination = "/vault/secrets/prometheus-auth"
  perms       = 0600
  command     = "docker-compose -f /opt/cloudya-infrastructure/docker-compose.production.yml restart prometheus"
}

template {
  source      = "/vault/templates/consul-auth.tpl"
  destination = "/vault/secrets/consul-auth"
  perms       = 0600
  command     = "docker-compose -f /opt/cloudya-infrastructure/docker-compose.production.yml restart consul"
}

template {
  source      = "/vault/templates/docker-compose-production.yml.tpl"
  destination = "/opt/cloudya-infrastructure/docker-compose-vault.yml"
  perms       = 0644
}
EOF

    # Store credentials for Vault Agent
    echo "$role_id" > "$PROJECT_ROOT/infrastructure/vault/agent/role_id"
    echo "$secret_id" > "$PROJECT_ROOT/infrastructure/vault/agent/secret_id"
    
    chmod 600 "$PROJECT_ROOT/infrastructure/vault/agent/role_id"
    chmod 600 "$PROJECT_ROOT/infrastructure/vault/agent/secret_id"
    
    log_success "Vault Agent configuration created"
}

# Configure auto-unseal
configure_auto_unseal() {
    log_info "Configuring Vault auto-unseal..."
    
    # Check if auto-unseal is already configured
    if vault status | grep -q "auto"; then
        log_info "Auto-unseal already configured"
        return 0
    fi
    
    # For production, recommend using cloud KMS
    # For now, create a transit seal configuration
    vault secrets enable -path=transit transit 2>/dev/null || log_info "Transit engine already enabled"
    
    vault write -f transit/keys/autounseal
    
    # Create auto-unseal policy
    cat > /tmp/autounseal-policy.hcl << EOF
path "transit/encrypt/autounseal" {
  capabilities = [ "update" ]
}

path "transit/decrypt/autounseal" {
  capabilities = [ "update" ]
}
EOF

    vault policy write autounseal /tmp/autounseal-policy.hcl
    rm /tmp/autounseal-policy.hcl
    
    # Create token for auto-unseal
    local autounseal_token=$(vault write -field=token auth/token/create \
        policies="autounseal" \
        no_parent=true \
        no_default_policy=true \
        renewable=true \
        ttl=768h \
        display_name="autounseal")
    
    # Store auto-unseal token securely
    echo "$autounseal_token" | vault kv put secret/cloudya/vault/autounseal token=-
    
    log_success "Auto-unseal configuration prepared"
    log_info "Manual step required: Update vault.hcl with auto-unseal configuration"
}

# Main execution
main() {
    log_info "Starting secrets migration automation..."
    
    # Enable KV engine
    enable_kv_engine
    
    # Create Vault policies
    create_vault_policies
    
    # Generate and store secure credentials
    generate_and_store_credentials
    
    # Create Vault Agent templates
    create_vault_agent_templates
    
    # Create Vault Agent configuration
    create_vault_agent_config
    
    # Configure auto-unseal
    configure_auto_unseal
    
    log_success "Secrets migration automation completed successfully!"
    log_info "Next steps:"
    log_info "1. Deploy Vault Agent service"
    log_info "2. Update docker-compose.production.yml to use Vault-generated secrets"
    log_info "3. Configure auto-unseal in vault.hcl"
    log_info "4. Test secret rotation"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi