#!/usr/bin/env bash
# Deployment Automation Script
# Updates all deployment scripts to use Vault for secrets instead of environment variables
#
# This script addresses CRITICAL compliance violations:
# - Removes hardcoded credentials from deployment scripts
# - Updates docker-compose configurations to use Vault Agent
# - Implements secure secret injection patterns

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
    echo -e "${BLUE}[DEPLOYMENT-AUTOMATION]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_DIR/deployment-automation.log"
}

log_success() {
    echo -e "${GREEN}[DEPLOYMENT-AUTOMATION]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_DIR/deployment-automation.log"
}

log_error() {
    echo -e "${RED}[DEPLOYMENT-AUTOMATION]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_DIR/deployment-automation.log" >&2
}

# Update docker-compose.production.yml to use Vault secrets
update_production_compose() {
    log_info "Updating docker-compose.production.yml to use Vault secrets..."
    
    local compose_file="$PROJECT_ROOT/docker-compose.production.yml"
    local backup_file="${compose_file}.pre-vault-backup"
    
    # Backup original file
    cp "$compose_file" "$backup_file"
    
    # Create new vault-integrated docker-compose file
    cat > "$compose_file" << 'EOF'
version: '3.8'

networks:
  cloudya:
    external: false
    driver: bridge
    ipam:
      config:
        - subnet: 172.25.0.0/16
  vault-internal:
    external: false
    driver: bridge
    internal: true

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
  # Vault Agent for secret management
  vault-agent:
    image: hashicorp/vault:1.17.6
    container_name: cloudya-vault-agent
    restart: unless-stopped
    networks:
      - cloudya
      - vault-internal
    volumes:
      - /opt/cloudya-infrastructure/vault/agent:/vault/config:ro
      - /opt/cloudya-infrastructure/secrets:/vault/secrets
      - /opt/cloudya-infrastructure/automation/templates:/vault/templates:ro
      - /opt/cloudya-infrastructure/automation/ssl-certs:/vault/certs:ro
    command: ["vault", "agent", "-config=/vault/config/agent.hcl"]
    environment:
      - VAULT_ADDR=https://vault.cloudya.net:8200
      - VAULT_SKIP_VERIFY=false
    healthcheck:
      test: ["CMD", "test", "-f", "/vault/secrets/token"]
      interval: 30s
      timeout: 10s
      retries: 5
    depends_on:
      vault:
        condition: service_healthy

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
      - /opt/cloudya-infrastructure/automation/ssl-certs/services:/consul/certs:ro
      - /opt/cloudya-infrastructure/secrets:/consul/secrets:ro
    command: ["consul", "agent", "-config-file=/consul/config/consul.hcl"]
    environment:
      - CONSUL_BIND_INTERFACE=eth0
      - CONSUL_CLIENT_INTERFACE=eth0
      - CONSUL_HTTP_TOKEN_FILE=/consul/secrets/consul-token
    healthcheck:
      test: ["CMD", "consul", "members"]
      interval: 30s
      timeout: 10s
      retries: 3
    depends_on:
      vault-agent:
        condition: service_healthy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.consul.rule=Host(`consul.cloudya.net`)"
      - "traefik.http.routers.consul.tls=true"
      - "traefik.http.routers.consul.tls.certresolver=letsencrypt"
      - "traefik.http.services.consul.loadbalancer.server.port=8500"
      - "traefik.http.middlewares.consul-auth.basicauth.usersfile=/vault/secrets/consul-auth"
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
      - /opt/cloudya-infrastructure/automation/ssl-certs:/vault/certs:ro
    cap_add:
      - IPC_LOCK
    command: ["vault", "server", "-config=/vault/config/vault.hcl"]
    environment:
      - VAULT_ADDR=https://0.0.0.0:8200
      - VAULT_API_ADDR=https://vault.cloudya.net:8200
      - VAULT_CLUSTER_ADDR=https://vault.cloudya.net:8201
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
      - /opt/cloudya-infrastructure/automation/ssl-certs/services:/nomad/certs:ro
      - /opt/cloudya-infrastructure/secrets:/nomad/secrets:ro
      - /var/run/docker.sock:/var/run/docker.sock
    command: ["nomad", "agent", "-config=/nomad/config/nomad.hcl"]
    environment:
      - NOMAD_TOKEN_FILE=/nomad/secrets/nomad-token
      - CONSUL_HTTP_TOKEN_FILE=/nomad/secrets/consul-token
    depends_on:
      consul:
        condition: service_healthy
      vault:
        condition: service_healthy
      vault-agent:
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
      - "traefik.http.services.nomad.loadbalancer.server.scheme=https"

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
      - /opt/cloudya-infrastructure/secrets:/etc/traefik/secrets:ro
      - /opt/cloudya-infrastructure/automation/ssl-certs:/etc/traefik/certs:ro
      - traefik_data:/letsencrypt
      - /var/run/docker.sock:/var/run/docker.sock:ro
    command:
      - "--configFile=/etc/traefik/traefik.yml"
    environment:
      - TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_EMAIL_FILE=/etc/traefik/secrets/acme-email
    depends_on:
      vault-agent:
        condition: service_healthy
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
      - "traefik.http.middlewares.dashboard-auth.basicauth.usersfile=/etc/traefik/secrets/traefik-auth"
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
      - /opt/cloudya-infrastructure/secrets:/etc/prometheus/secrets:ro
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
      - '--web.enable-lifecycle'
      - '--web.external-url=https://prometheus.cloudya.net'
    depends_on:
      vault-agent:
        condition: service_healthy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.prometheus.rule=Host(`prometheus.cloudya.net`)"
      - "traefik.http.routers.prometheus.tls=true"
      - "traefik.http.routers.prometheus.tls.certresolver=letsencrypt"
      - "traefik.http.services.prometheus.loadbalancer.server.port=9090"
      - "traefik.http.middlewares.prometheus-auth.basicauth.usersfile=/etc/prometheus/secrets/prometheus-auth"
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
      - /opt/cloudya-infrastructure/secrets:/etc/grafana/secrets:ro
    env_file:
      - /opt/cloudya-infrastructure/secrets/grafana.env
    user: "472:472"
    depends_on:
      vault-agent:
        condition: service_healthy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.grafana.rule=Host(`grafana.cloudya.net`)"
      - "traefik.http.routers.grafana.tls=true"
      - "traefik.http.routers.grafana.tls.certresolver=letsencrypt"
      - "traefik.http.services.grafana.loadbalancer.server.port=3000"

  # Secret rotation service
  secret-rotator:
    image: hashicorp/vault:1.17.6
    container_name: cloudya-secret-rotator
    restart: unless-stopped
    networks:
      - vault-internal
    volumes:
      - /opt/cloudya-infrastructure/automation/rotation-scripts:/scripts:ro
      - /opt/cloudya-infrastructure/secrets:/secrets
      - /var/log/cloudya-security:/logs
    environment:
      - VAULT_ADDR=https://vault.cloudya.net:8200
      - VAULT_TOKEN_FILE=/secrets/rotation-token
    command: ["sh", "-c", "while true; do sleep 21600; /scripts/rotation-engine.sh rotate; done"]
    depends_on:
      vault:
        condition: service_healthy
      vault-agent:
        condition: service_healthy
EOF

    log_success "Updated docker-compose.production.yml with Vault integration"
}

# Create secure deployment scripts
create_secure_deployment_scripts() {
    log_info "Creating secure deployment scripts..."
    
    mkdir -p "$PROJECT_ROOT/automation/deployment-scripts"
    
    # Main deployment script
    cat > "$PROJECT_ROOT/automation/deployment-scripts/deploy-secure.sh" << 'EOF'
#!/usr/bin/env bash
# Secure Deployment Script
# Deploys CloudYa infrastructure using Vault for secret management

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
VAULT_ADDR="${VAULT_ADDR:-https://vault.cloudya.net:8200}"
ENVIRONMENT="${ENVIRONMENT:-production}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[DEPLOY]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_success() {
    echo -e "${GREEN}[DEPLOY]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_error() {
    echo -e "${RED}[DEPLOY]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating deployment prerequisites..."
    
    # Check required commands
    local required_commands=("docker" "docker-compose" "vault" "jq")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Required command not found: $cmd"
            return 1
        fi
    done
    
    # Check Vault accessibility
    if ! vault status >/dev/null 2>&1; then
        log_error "Vault is not accessible at $VAULT_ADDR"
        return 1
    fi
    
    # Check required directories
    local required_dirs=(
        "/opt/cloudya-data"
        "/opt/cloudya-infrastructure"
        "/opt/cloudya-infrastructure/secrets"
        "/opt/cloudya-infrastructure/automation"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_error "Required directory not found: $dir"
            return 1
        fi
    done
    
    log_success "Prerequisites validated"
}

# Setup secrets directory
setup_secrets_directory() {
    log_info "Setting up secrets directory..."
    
    local secrets_dir="/opt/cloudya-infrastructure/secrets"
    
    # Ensure proper ownership and permissions
    sudo mkdir -p "$secrets_dir"
    sudo chown -R root:docker "$secrets_dir"
    sudo chmod -R 750 "$secrets_dir"
    
    # Create subdirectories for different secret types
    local secret_subdirs=(
        "tokens"
        "certificates" 
        "auth-files"
        "config-files"
    )
    
    for subdir in "${secret_subdirs[@]}"; do
        sudo mkdir -p "$secrets_dir/$subdir"
        sudo chmod 700 "$secrets_dir/$subdir"
    done
    
    log_success "Secrets directory configured"
}

# Deploy Vault Agent configuration
deploy_vault_agent() {
    log_info "Deploying Vault Agent configuration..."
    
    local agent_dir="/opt/cloudya-infrastructure/vault/agent"
    
    # Ensure Vault Agent has proper AppRole credentials
    if [[ ! -f "$agent_dir/role_id" ]] || [[ ! -f "$agent_dir/secret_id" ]]; then
        log_error "Vault Agent credentials not found. Run secrets migration first."
        return 1
    fi
    
    # Validate AppRole authentication
    local role_id=$(cat "$agent_dir/role_id")
    local secret_id=$(cat "$agent_dir/secret_id")
    
    if ! vault write auth/approle/login role_id="$role_id" secret_id="$secret_id" >/dev/null 2>&1; then
        log_error "Vault Agent AppRole authentication failed"
        return 1
    fi
    
    log_success "Vault Agent configuration validated"
}

# Pre-deployment security checks
pre_deployment_security_checks() {
    log_info "Running pre-deployment security checks..."
    
    # Check for hardcoded credentials
    local compose_file="$PROJECT_ROOT/docker-compose.production.yml"
    if grep -q "password.*=" "$compose_file" 2>/dev/null; then
        log_error "Hardcoded passwords detected in docker-compose file"
        return 1
    fi
    
    if grep -q "\$\$2y\$\$10\$\$" "$compose_file" 2>/dev/null; then
        log_error "Hardcoded bcrypt hashes detected in docker-compose file"
        return 1
    fi
    
    # Verify SSL certificates are available
    local cert_dir="$PROJECT_ROOT/automation/ssl-certs/services"
    local required_certs=("vault.crt" "consul.crt" "nomad.crt" "traefik.crt")
    
    for cert in "${required_certs[@]}"; do
        if [[ ! -f "$cert_dir/$cert" ]]; then
            log_error "Required SSL certificate not found: $cert"
            return 1
        fi
        
        # Check certificate expiration (warn if < 30 days)
        if ! openssl x509 -in "$cert_dir/$cert" -noout -checkend 2592000; then
            log_error "SSL certificate expires within 30 days: $cert"
            return 1
        fi
    done
    
    log_success "Pre-deployment security checks passed"
}

# Deploy services
deploy_services() {
    log_info "Deploying CloudYa services..."
    
    local compose_file="$PROJECT_ROOT/docker-compose.production.yml"
    
    # Pull latest images
    log_info "Pulling latest container images..."
    docker-compose -f "$compose_file" pull
    
    # Start services in dependency order
    log_info "Starting Consul service..."
    docker-compose -f "$compose_file" up -d consul
    
    # Wait for Consul to be healthy
    log_info "Waiting for Consul to be healthy..."
    local max_attempts=30
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if docker-compose -f "$compose_file" ps consul | grep -q "healthy"; then
            log_success "Consul is healthy"
            break
        fi
        log_info "Attempt $attempt/$max_attempts: Waiting for Consul..."
        sleep 10
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        log_error "Consul failed to become healthy"
        return 1
    fi
    
    # Start Vault
    log_info "Starting Vault service..."
    docker-compose -f "$compose_file" up -d vault
    
    # Wait for Vault to be healthy
    log_info "Waiting for Vault to be healthy..."
    attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if docker-compose -f "$compose_file" ps vault | grep -q "healthy"; then
            log_success "Vault is healthy"
            break
        fi
        log_info "Attempt $attempt/$max_attempts: Waiting for Vault..."
        sleep 10
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        log_error "Vault failed to become healthy"
        return 1
    fi
    
    # Start Vault Agent
    log_info "Starting Vault Agent..."
    docker-compose -f "$compose_file" up -d vault-agent
    
    # Wait for Vault Agent to generate secrets
    log_info "Waiting for Vault Agent to generate secrets..."
    sleep 30
    
    # Start remaining services
    log_info "Starting remaining services..."
    docker-compose -f "$compose_file" up -d
    
    log_success "All services deployed"
}

# Post-deployment validation
post_deployment_validation() {
    log_info "Running post-deployment validation..."
    
    local compose_file="$PROJECT_ROOT/docker-compose.production.yml"
    
    # Check service health
    local services=$(docker-compose -f "$compose_file" config --services)
    local unhealthy_services=()
    
    for service in $services; do
        if ! docker-compose -f "$compose_file" ps "$service" | grep -q "healthy\|Up"; then
            unhealthy_services+=("$service")
        fi
    done
    
    if [[ ${#unhealthy_services[@]} -gt 0 ]]; then
        log_error "Unhealthy services: ${unhealthy_services[*]}"
        return 1
    fi
    
    # Test service endpoints
    local endpoints=(
        "https://consul.cloudya.net/v1/status/leader"
        "https://vault.cloudya.net/v1/sys/health"
        "https://nomad.cloudya.net/v1/status/leader"
        "https://traefik.cloudya.net/ping"
    )
    
    for endpoint in "${endpoints[@]}"; do
        if ! curl -f -s -k "$endpoint" >/dev/null 2>&1; then
            log_error "Service endpoint not responding: $endpoint"
            return 1
        fi
    done
    
    # Verify secret injection is working
    if [[ ! -f "/opt/cloudya-infrastructure/secrets/traefik-auth" ]]; then
        log_error "Vault Agent secret injection not working"
        return 1
    fi
    
    log_success "Post-deployment validation passed"
}

# Generate deployment report
generate_deployment_report() {
    log_info "Generating deployment report..."
    
    local report_file="/var/log/cloudya-security/deployment-report-$(date +%Y%m%d-%H%M%S).json"
    local compose_file="$PROJECT_ROOT/docker-compose.production.yml"
    
    cat > "$report_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "environment": "$ENVIRONMENT",
  "deployment_status": "success",
  "services": [
EOF

    local services=$(docker-compose -f "$compose_file" config --services)
    local first=true
    
    for service in $services; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "    ," >> "$report_file"
        fi
        
        local status=$(docker-compose -f "$compose_file" ps "$service" --format "table {{.State}}" | tail -n1 || echo "unknown")
        local image=$(docker-compose -f "$compose_file" images "$service" --format "table {{.Repository}}:{{.Tag}}" | tail -n1 || echo "unknown")
        
        cat >> "$report_file" << EOF
    {
      "name": "$service",
      "status": "$status",
      "image": "$image"
    }
EOF
    done
    
    cat >> "$report_file" << EOF
  ],
  "security_features": {
    "vault_integration": true,
    "ssl_certificates": true,
    "acl_enabled": true,
    "secret_rotation": true,
    "vault_agent": true
  },
  "endpoints": {
    "consul": "https://consul.cloudya.net",
    "vault": "https://vault.cloudya.net",
    "nomad": "https://nomad.cloudya.net",
    "traefik": "https://traefik.cloudya.net",
    "prometheus": "https://prometheus.cloudya.net",
    "grafana": "https://grafana.cloudya.net"
  }
}
EOF

    log_success "Deployment report generated: $report_file"
}

# Main deployment flow
main() {
    log_info "Starting secure CloudYa deployment..."
    
    validate_prerequisites
    setup_secrets_directory
    deploy_vault_agent
    pre_deployment_security_checks
    deploy_services
    post_deployment_validation
    generate_deployment_report
    
    log_success "Secure deployment completed successfully!"
    log_info "Services are accessible at:"
    log_info "  - Consul: https://consul.cloudya.net"
    log_info "  - Vault: https://vault.cloudya.net"
    log_info "  - Nomad: https://nomad.cloudya.net"
    log_info "  - Traefik: https://traefik.cloudya.net"
    log_info "  - Prometheus: https://prometheus.cloudya.net"
    log_info "  - Grafana: https://grafana.cloudya.net"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
EOF

    chmod +x "$PROJECT_ROOT/automation/deployment-scripts/deploy-secure.sh"
    
    log_success "Secure deployment script created"
}

# Update Traefik configuration for Vault integration
update_traefik_config() {
    log_info "Updating Traefik configuration for Vault integration..."
    
    local traefik_config="$PROJECT_ROOT/infrastructure/traefik/config/traefik.yml"
    local backup_config="${traefik_config}.vault-backup"
    
    # Backup original config
    cp "$traefik_config" "$backup_config"
    
    # Update Traefik config to use secrets from files
    cat > "$traefik_config" << 'EOF'
# Global Configuration
global:
  checkNewVersion: false
  sendAnonymousUsage: false

# API and Dashboard
api:
  dashboard: true
  debug: false

# Entry Points
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"
    http:
      tls:
        options: default
        certResolver: letsencrypt

# Certificate Resolvers
certificatesResolvers:
  letsencrypt:
    acme:
      email: "{{env `TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_EMAIL_FILE`}}"
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
      keyType: EC256

# TLS Configuration
tls:
  options:
    default:
      minVersion: "VersionTLS13"
      cipherSuites:
        - "TLS_AES_256_GCM_SHA384"
        - "TLS_CHACHA20_POLY1305_SHA256"
        - "TLS_AES_128_GCM_SHA256"

# Providers
providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: cloudya
    watch: true
  
  file:
    directory: /etc/traefik/dynamic
    watch: true

# Consul Catalog Provider
  consulCatalog:
    endpoints:
      - "consul.cloudya.net:8500"
    prefix: traefik
    exposedByDefault: false
    watch: true
    
    # Consul authentication using token from file
    token: "{{env `CONSUL_HTTP_TOKEN_FILE`}}"
    
    # TLS configuration for Consul
    tls:
      ca: /etc/traefik/certs/consul-ca.crt
      cert: /etc/traefik/certs/consul-client.crt
      key: /etc/traefik/certs/consul-client.key
      insecureSkipVerify: false

# Metrics
metrics:
  prometheus:
    addEntryPointsLabels: true
    addServicesLabels: true
    buckets:
      - 0.1
      - 0.3
      - 1.2
      - 5.0

# Tracing
tracing:
  otlp:
    http:
      endpoint: "http://jaeger:14268/api/traces"

# Logging
log:
  level: INFO
  format: json

accessLog:
  format: json
  fields:
    defaultMode: keep
    headers:
      defaultMode: drop
      names:
        Authorization: drop
        Cookie: drop

# Ping endpoint
ping: {}

# Health check
healthcheck: {}
EOF

    # Update dynamic configuration to use basic auth from files
    local dynamic_config="$PROJECT_ROOT/infrastructure/traefik/config/dynamic/middlewares.yml"
    
    cat > "$dynamic_config" << 'EOF'
http:
  middlewares:
    # Security Headers
    security-headers:
      headers:
        frameDeny: true
        sslRedirect: true
        browserXssFilter: true
        contentTypeNosniff: true
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 31536000
        customFrameOptionsValue: "SAMEORIGIN"
        customRequestHeaders:
          X-Forwarded-Proto: "https"
        customResponseHeaders:
          X-Robots-Tag: "noindex,nofollow,nosnippet,noarchive"
          X-Frame-Options: "SAMEORIGIN"
          Referrer-Policy: "strict-origin-when-cross-origin"

    # Rate Limiting
    rate-limit:
      rateLimit:
        burst: 100
        period: 1m
        average: 50

    # IP Whitelist for admin interfaces
    admin-whitelist:
      ipWhiteList:
        sourceRange:
          - "127.0.0.1/32"
          - "10.0.0.0/8"
          - "172.16.0.0/12"
          - "192.168.0.0/16"

    # Basic Authentication using files generated by Vault Agent
    traefik-auth:
      basicAuth:
        usersFile: "/etc/traefik/secrets/traefik-auth"
        removeHeader: true

    consul-auth:
      basicAuth:
        usersFile: "/etc/traefik/secrets/consul-auth"
        removeHeader: true

    prometheus-auth:
      basicAuth:
        usersFile: "/etc/traefik/secrets/prometheus-auth"
        removeHeader: true

    # Compress responses
    compression:
      compress: true

    # Circuit breaker
    circuit-breaker:
      expression: "NetworkErrorRatio() > 0.5"
      checkPeriod: "3s"
      fallbackDuration: "10s"
      recoveryDuration: "10s"

    # Retry middleware
    retry:
      attempts: 3
      initialInterval: "100ms"

  # TLS Configuration
  tls:
    options:
      default:
        minVersion: "VersionTLS13"
        cipherSuites:
          - "TLS_AES_256_GCM_SHA384"
          - "TLS_CHACHA20_POLY1305_SHA256"
          - "TLS_AES_128_GCM_SHA256"
        sniStrict: true

    stores:
      default:
        defaultCertificate:
          certFile: /etc/traefik/certs/traefik.crt
          keyFile: /etc/traefik/certs/traefik.key
EOF

    log_success "Traefik configuration updated for Vault integration"
}

# Create environment-specific configuration templates
create_environment_configs() {
    log_info "Creating environment-specific configuration templates..."
    
    mkdir -p "$PROJECT_ROOT/automation/deployment-scripts/environments"
    
    # Production environment configuration
    cat > "$PROJECT_ROOT/automation/deployment-scripts/environments/production.env" << 'EOF'
# Production Environment Configuration
ENVIRONMENT=production
VAULT_ADDR=https://vault.cloudya.net:8200
CONSUL_HTTP_ADDR=https://consul.cloudya.net:8500
NOMAD_ADDR=https://nomad.cloudya.net:4646

# Security Settings
VAULT_SKIP_VERIFY=false
CONSUL_HTTP_SSL=true
NOMAD_TLS_ENABLE=true

# Logging
LOG_LEVEL=INFO
AUDIT_LOG_LEVEL=TRACE

# Monitoring
ENABLE_METRICS=true
METRICS_INTERVAL=30s

# Backup
BACKUP_RETENTION_DAYS=30
SNAPSHOT_INTERVAL=24h

# Alerting
ALERT_EMAIL=admin@cloudya.net
ALERT_WEBHOOK_URL=
EOF

    # Staging environment configuration
    cat > "$PROJECT_ROOT/automation/deployment-scripts/environments/staging.env" << 'EOF'
# Staging Environment Configuration
ENVIRONMENT=staging
VAULT_ADDR=https://vault-staging.cloudya.net:8200
CONSUL_HTTP_ADDR=https://consul-staging.cloudya.net:8500
NOMAD_ADDR=https://nomad-staging.cloudya.net:4646

# Security Settings
VAULT_SKIP_VERIFY=false
CONSUL_HTTP_SSL=true
NOMAD_TLS_ENABLE=true

# Logging
LOG_LEVEL=DEBUG
AUDIT_LOG_LEVEL=TRACE

# Monitoring
ENABLE_METRICS=true
METRICS_INTERVAL=10s

# Backup
BACKUP_RETENTION_DAYS=7
SNAPSHOT_INTERVAL=12h

# Alerting
ALERT_EMAIL=staging-alerts@cloudya.net
ALERT_WEBHOOK_URL=
EOF

    # Development environment configuration
    cat > "$PROJECT_ROOT/automation/deployment-scripts/environments/development.env" << 'EOF'
# Development Environment Configuration
ENVIRONMENT=development
VAULT_ADDR=https://vault-dev.cloudya.net:8200
CONSUL_HTTP_ADDR=https://consul-dev.cloudya.net:8500
NOMAD_ADDR=https://nomad-dev.cloudya.net:4646

# Security Settings (relaxed for development)
VAULT_SKIP_VERIFY=true
CONSUL_HTTP_SSL=false
NOMAD_TLS_ENABLE=false

# Logging
LOG_LEVEL=DEBUG
AUDIT_LOG_LEVEL=DEBUG

# Monitoring
ENABLE_METRICS=true
METRICS_INTERVAL=5s

# Backup
BACKUP_RETENTION_DAYS=3
SNAPSHOT_INTERVAL=6h

# Alerting
ALERT_EMAIL=dev-alerts@cloudya.net
ALERT_WEBHOOK_URL=
EOF

    log_success "Environment-specific configurations created"
}

# Create GitHub Actions workflow for secure deployment
create_github_workflow() {
    log_info "Creating GitHub Actions workflow for secure deployment..."
    
    mkdir -p "$PROJECT_ROOT/.github/workflows"
    
    cat > "$PROJECT_ROOT/.github/workflows/deploy-secure.yml" << 'EOF'
name: Secure CloudYa Deployment

on:
  push:
    branches:
      - main
      - develop
  pull_request:
    branches:
      - main
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to deploy to'
        required: true
        default: 'staging'
        type: choice
        options:
          - staging
          - production

env:
  VAULT_ADDR: ${{ secrets.VAULT_ADDR }}
  VAULT_TOKEN: ${{ secrets.VAULT_TOKEN }}

jobs:
  security-scan:
    name: Security Scan
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Run security scan
        run: |
          # Scan for hardcoded secrets
          if grep -r "password.*=" . --include="*.yml" --include="*.yaml" --exclude-dir=".git"; then
            echo "❌ Hardcoded passwords found"
            exit 1
          fi
          
          if grep -r "\$\$2y\$\$10\$\$" . --include="*.yml" --exclude-dir=".git"; then
            echo "❌ Hardcoded bcrypt hashes found"
            exit 1
          fi
          
          echo "✅ No hardcoded secrets found"

      - name: Validate Docker Compose
        run: |
          docker-compose -f docker-compose.production.yml config > /dev/null
          echo "✅ Docker Compose configuration is valid"

  deploy-staging:
    name: Deploy to Staging
    runs-on: self-hosted
    if: github.ref == 'refs/heads/develop' || (github.event_name == 'workflow_dispatch' && github.event.inputs.environment == 'staging')
    needs: security-scan
    environment: staging
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Vault CLI
        uses: hashicorp/setup-vault@v1
        with:
          vault_version: 1.17.6

      - name: Authenticate with Vault
        run: |
          echo "$VAULT_TOKEN" | vault auth -method=token -
          vault token lookup

      - name: Run pre-deployment checks
        run: |
          # Check Vault accessibility
          vault status
          
          # Verify required secrets exist
          vault kv list secret/cloudya/
          
          # Check SSL certificates
          vault read pki/cert/ca

      - name: Deploy to staging
        env:
          ENVIRONMENT: staging
        run: |
          # Load environment configuration
          source automation/deployment-scripts/environments/staging.env
          
          # Run secure deployment
          automation/deployment-scripts/deploy-secure.sh

      - name: Run post-deployment tests
        run: |
          # Wait for services to be ready
          sleep 60
          
          # Test service endpoints
          curl -f https://consul-staging.cloudya.net/v1/status/leader
          curl -f -k https://vault-staging.cloudya.net/v1/sys/health
          curl -f https://nomad-staging.cloudya.net/v1/status/leader
          curl -f https://traefik-staging.cloudya.net/ping

  deploy-production:
    name: Deploy to Production
    runs-on: self-hosted
    if: github.ref == 'refs/heads/main' || (github.event_name == 'workflow_dispatch' && github.event.inputs.environment == 'production')
    needs: security-scan
    environment: production
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Vault CLI
        uses: hashicorp/setup-vault@v1
        with:
          vault_version: 1.17.6

      - name: Authenticate with Vault
        run: |
          echo "$VAULT_TOKEN" | vault auth -method=token -
          vault token lookup

      - name: Create deployment backup
        run: |
          # Backup current configuration
          vault kv get -format=json secret/cloudya/ > backup-$(date +%Y%m%d-%H%M%S).json
          
          # Create Consul snapshot
          consul snapshot save backup-consul-$(date +%Y%m%d-%H%M%S).snap

      - name: Run pre-deployment checks
        run: |
          # Check Vault accessibility
          vault status
          
          # Verify required secrets exist
          vault kv list secret/cloudya/
          
          # Check SSL certificates (must have > 7 days until expiry)
          if ! openssl x509 -in automation/ssl-certs/services/vault.crt -noout -checkend 604800; then
            echo "❌ SSL certificates expire within 7 days"
            exit 1
          fi

      - name: Deploy to production
        env:
          ENVIRONMENT: production
        run: |
          # Load environment configuration
          source automation/deployment-scripts/environments/production.env
          
          # Run secure deployment with extra validation
          automation/deployment-scripts/deploy-secure.sh

      - name: Run production validation
        run: |
          # Wait for services to be ready
          sleep 120
          
          # Test all service endpoints
          curl -f https://consul.cloudya.net/v1/status/leader
          curl -f -k https://vault.cloudya.net/v1/sys/health
          curl -f https://nomad.cloudya.net/v1/status/leader
          curl -f https://traefik.cloudya.net/ping
          curl -f https://prometheus.cloudya.net/-/healthy
          curl -f https://grafana.cloudya.net/api/health

      - name: Notify deployment success
        run: |
          # Send success notification (implement your preferred method)
          echo "✅ Production deployment completed successfully"

  rollback:
    name: Rollback Deployment
    runs-on: self-hosted
    if: failure()
    steps:
      - name: Rollback deployment
        run: |
          echo "🔄 Rolling back deployment..."
          # Implement rollback logic here
          # This could restore from backup, revert to previous version, etc.
EOF

    log_success "GitHub Actions workflow created"
}

# Main execution
main() {
    log_info "Starting deployment automation configuration..."
    
    # Update main docker-compose file
    update_production_compose
    
    # Create secure deployment scripts
    create_secure_deployment_scripts
    
    # Update Traefik configuration
    update_traefik_config
    
    # Create environment-specific configurations
    create_environment_configs
    
    # Create GitHub Actions workflow
    create_github_workflow
    
    log_success "Deployment automation completed successfully!"
    log_info "Updated configurations:"
    log_info "  - docker-compose.production.yml (Vault-integrated)"
    log_info "  - automation/deployment-scripts/deploy-secure.sh"
    log_info "  - infrastructure/traefik/config/ (updated for Vault)"
    log_info "  - .github/workflows/deploy-secure.yml"
    log_info "Next steps:"
    log_info "  1. Test the secure deployment script"
    log_info "  2. Verify Vault Agent secret injection"
    log_info "  3. Update CI/CD pipelines to use new workflow"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi