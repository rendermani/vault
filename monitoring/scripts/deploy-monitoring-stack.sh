#!/bin/bash
# Deploy Comprehensive Monitoring Stack for HashiCorp Infrastructure
# This script deploys the complete monitoring solution including OTEL, Prometheus, Grafana, Loki, and Alertmanager

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITORING_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$MONITORING_DIR")"

# Default values
ENVIRONMENT="${ENVIRONMENT:-production}"
CONSUL_ADDR="${CONSUL_HTTP_ADDR:-http://localhost:8500}"
NOMAD_ADDR="${NOMAD_ADDR:-http://localhost:4646}"
VAULT_ADDR="${VAULT_ADDR:-https://vault.cloudya.net}"
DOCKER_NETWORK="${DOCKER_NETWORK:-cloudya-monitoring}"
DATA_PATH="${DATA_PATH:-/opt/cloudya-data/monitoring}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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
    
    local missing_tools=()
    
    for tool in docker docker-compose nomad consul curl jq; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
    
    # Check connectivity to HashiCorp services
    if ! curl -s "$CONSUL_ADDR/v1/status/leader" &> /dev/null; then
        log_warning "Consul not reachable at $CONSUL_ADDR"
    fi
    
    if ! curl -s "$NOMAD_ADDR/v1/status/leader" &> /dev/null; then
        log_warning "Nomad not reachable at $NOMAD_ADDR"
    fi
    
    log_success "Prerequisites check completed"
}

# Create necessary directories
setup_directories() {
    log_info "Setting up monitoring directories..."
    
    local dirs=(
        "$DATA_PATH/prometheus"
        "$DATA_PATH/grafana"
        "$DATA_PATH/alertmanager"
        "$DATA_PATH/loki"
        "$DATA_PATH/redis"
        "$DATA_PATH/otel"
        "/var/log/cloudya/monitoring"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_info "Creating directory: $dir"
            sudo mkdir -p "$dir"
            sudo chown -R "$(id -u):$(id -g)" "$dir"
        fi
    done
    
    log_success "Directories created successfully"
}

# Generate secrets and tokens
generate_secrets() {
    log_info "Generating monitoring secrets..."
    
    local secrets_file="$MONITORING_DIR/.env"
    
    if [[ ! -f "$secrets_file" ]]; then
        cat > "$secrets_file" <<EOF
# Monitoring Stack Environment Variables
ENVIRONMENT=$ENVIRONMENT

# Grafana Configuration
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=$(openssl rand -hex 16)
GRAFANA_SECRET_KEY=$(openssl rand -hex 32)

# SMTP Configuration (update with your values)
SMTP_PASSWORD=your-smtp-password

# Slack Webhook (update with your webhook URL)
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK

# PagerDuty Integration Keys (update with your keys)
PAGERDUTY_INTEGRATION_KEY=your-pagerduty-integration-key
PAGERDUTY_VAULT_KEY=your-vault-specific-key
PAGERDUTY_NOMAD_KEY=your-nomad-specific-key
PAGERDUTY_CONSUL_KEY=your-consul-specific-key
PAGERDUTY_SECURITY_KEY=your-security-key

# Webhook Authentication
WEBHOOK_TOKEN=$(openssl rand -hex 32)

# External OTEL API Key (if using external vendor)
EXTERNAL_OTEL_API_KEY=your-external-otel-key
EOF
        log_success "Secrets file created at $secrets_file"
        log_warning "Please update the secrets in $secrets_file with your actual values"
    else
        log_info "Secrets file already exists"
    fi
}

# Setup Prometheus configuration
setup_prometheus() {
    log_info "Setting up Prometheus configuration..."
    
    # Copy enhanced Prometheus config
    cp "$MONITORING_DIR/enhanced-prometheus-config.yml" "$DATA_PATH/prometheus/prometheus.yml"
    
    # Create alert rules directory
    mkdir -p "$DATA_PATH/prometheus/rules/hashicorp"
    mkdir -p "$DATA_PATH/prometheus/rules/infrastructure"
    mkdir -p "$DATA_PATH/prometheus/rules/security"
    
    # Copy alert rules
    cp "$MONITORING_DIR/alert-rules"/*.yml "$DATA_PATH/prometheus/rules/hashicorp/"
    
    # Generate Vault token for Prometheus (if Vault is available)
    if curl -s "$VAULT_ADDR/v1/sys/health" &> /dev/null; then
        log_info "Generating Vault token for Prometheus..."
        # Note: This requires proper Vault authentication
        # vault auth -method=userpass username=prometheus
        # vault write -field=token auth/userpass/login/prometheus > "$DATA_PATH/prometheus/vault-token"
        log_warning "Vault token generation skipped - configure manually"
        echo "prometheus-vault-token-placeholder" > "$DATA_PATH/prometheus/vault-token"
    fi
    
    log_success "Prometheus configuration completed"
}

# Setup Grafana
setup_grafana() {
    log_info "Setting up Grafana configuration..."
    
    # Create Grafana provisioning directories
    mkdir -p "$DATA_PATH/grafana/provisioning/datasources"
    mkdir -p "$DATA_PATH/grafana/provisioning/dashboards"
    mkdir -p "$DATA_PATH/grafana/dashboards"
    
    # Create datasources configuration
    cat > "$DATA_PATH/grafana/provisioning/datasources/datasources.yml" <<EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    jsonData:
      timeInterval: 15s
  
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    jsonData:
      maxLines: 1000
  
  - name: Jaeger
    type: jaeger
    access: proxy
    url: http://jaeger:16686
    jsonData:
      tracesToLogsV2:
        datasourceUid: loki
        spanStartTimeShift: '-1h'
        spanEndTimeShift: '1h'
        tags: ['job', 'instance', 'pod', 'namespace']
        filterByTraceID: false
        filterBySpanID: false
        customQuery: true
        query: '{service_name="${__span.tags.service.name}"} |= "${__trace.traceID}"'
EOF

    # Create dashboards provisioning
    cat > "$DATA_PATH/grafana/provisioning/dashboards/dashboards.yml" <<EOF
apiVersion: 1

providers:
  - name: 'HashiCorp Dashboards'
    orgId: 1
    folder: 'HashiCorp'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOF

    # Copy dashboard files
    cp "$MONITORING_DIR/dashboards"/*.json "$DATA_PATH/grafana/dashboards/"
    
    log_success "Grafana configuration completed"
}

# Setup Loki
setup_loki() {
    log_info "Setting up Loki configuration..."
    
    # Copy Loki config
    cp "$MONITORING_DIR/loki-config.yaml" "$DATA_PATH/loki/loki.yml"
    
    # Copy Promtail config
    cp "$MONITORING_DIR/promtail-config.yaml" "$DATA_PATH/loki/promtail.yml"
    
    log_success "Loki configuration completed"
}

# Setup Alertmanager
setup_alertmanager() {
    log_info "Setting up Alertmanager configuration..."
    
    # Copy Alertmanager config
    cp "$MONITORING_DIR/alertmanager-config.yml" "$DATA_PATH/alertmanager/alertmanager.yml"
    
    # Create alert templates directory
    mkdir -p "$DATA_PATH/alertmanager/templates"
    
    # Create basic alert template
    cat > "$DATA_PATH/alertmanager/templates/default.tmpl" <<EOF
{{ define "slack.default.title" }}
[{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}] {{ .GroupLabels.alertname }}
{{ end }}

{{ define "slack.default.text" }}
{{ range .Alerts }}
{{if .Annotations.summary}}*Summary:* {{ .Annotations.summary }}{{ end }}
{{if .Annotations.description}}*Description:* {{ .Annotations.description }}{{ end }}
*Details:*
{{ range .Labels.SortedPairs }} • *{{ .Name }}:* {{ .Value }}
{{ end }}
{{ end }}
{{ end }}
EOF
    
    log_success "Alertmanager configuration completed"
}

# Setup OpenTelemetry
setup_otel() {
    log_info "Setting up OpenTelemetry configuration..."
    
    # Copy OTEL collector config
    cp "$MONITORING_DIR/otel-collector-config.yaml" "$DATA_PATH/otel/otel-config.yml"
    
    # Create certificates directory for OTEL
    mkdir -p "$DATA_PATH/otel/tls"
    
    # Generate self-signed certificates for testing (replace with proper certs in production)
    if [[ ! -f "$DATA_PATH/otel/tls/cert.pem" ]]; then
        log_info "Generating self-signed certificates for OTEL (use proper certs in production)"
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$DATA_PATH/otel/tls/key.pem" \
            -out "$DATA_PATH/otel/tls/cert.pem" \
            -subj "/C=US/ST=State/L=City/O=Organization/OU=OrgUnit/CN=otel-collector"
        cp "$DATA_PATH/otel/tls/cert.pem" "$DATA_PATH/otel/tls/ca.pem"
    fi
    
    log_success "OpenTelemetry configuration completed"
}

# Deploy OTEL Collector via Nomad
deploy_otel_nomad() {
    log_info "Deploying OTEL Collector to Nomad..."
    
    nomad job run - <<EOF
job "otel-collector" {
  datacenters = ["dc1"]
  type = "service"
  
  group "collector" {
    count = 2
    
    network {
      port "otlp-grpc" {
        static = 4317
      }
      port "otlp-http" {
        static = 4318
      }
      port "prometheus" {
        static = 8889
      }
      port "health" {
        static = 13133
      }
    }
    
    service {
      name = "otel-collector"
      port = "otlp-grpc"
      tags = ["otel", "collector", "monitoring"]
      
      check {
        type = "http"
        port = "health"
        path = "/health"
        interval = "30s"
        timeout = "5s"
      }
      
      meta {
        version = "0.88.0"
        protocol = "otlp"
      }
    }
    
    task "otel-collector" {
      driver = "docker"
      
      config {
        image = "otel/opentelemetry-collector-contrib:0.88.0"
        args = ["--config=/local/otel-config.yml"]
        ports = ["otlp-grpc", "otlp-http", "prometheus", "health"]
      }
      
      template {
        data = <<EOH
$(cat "$MONITORING_DIR/otel-collector-config.yaml")
EOH
        destination = "local/otel-config.yml"
      }
      
      resources {
        cpu = 1000
        memory = 2048
      }
    }
  }
}
EOF
    
    log_success "OTEL Collector deployed to Nomad"
}

# Create monitoring network
create_network() {
    log_info "Creating Docker monitoring network..."
    
    if ! docker network ls | grep -q "$DOCKER_NETWORK"; then
        docker network create \
            --driver bridge \
            --subnet=172.21.0.0/16 \
            "$DOCKER_NETWORK"
        log_success "Docker network '$DOCKER_NETWORK' created"
    else
        log_info "Docker network '$DOCKER_NETWORK' already exists"
    fi
}

# Deploy monitoring stack
deploy_stack() {
    log_info "Deploying monitoring stack with Docker Compose..."
    
    cd "$MONITORING_DIR"
    
    # Use the existing docker-compose.monitoring.yml but with our configurations
    docker-compose -f "../infrastructure/monitoring/docker-compose.monitoring.yml" up -d
    
    log_success "Monitoring stack deployed successfully"
}

# Wait for services to be ready
wait_for_services() {
    log_info "Waiting for services to be ready..."
    
    local services=(
        "prometheus:9090:/metrics"
        "grafana:3000:/api/health"
        "alertmanager:9093:/-/healthy"
        "loki:3100:/ready"
    )
    
    for service in "${services[@]}"; do
        IFS=':' read -r name port path <<< "$service"
        log_info "Waiting for $name to be ready..."
        
        local max_attempts=30
        local attempt=1
        
        while [[ $attempt -le $max_attempts ]]; do
            if curl -s "http://localhost:$port$path" &> /dev/null; then
                log_success "$name is ready"
                break
            fi
            
            if [[ $attempt -eq $max_attempts ]]; then
                log_error "$name failed to start within expected time"
                return 1
            fi
            
            sleep 10
            ((attempt++))
        done
    done
    
    log_success "All services are ready"
}

# Configure HashiCorp services for monitoring
configure_hashicorp_monitoring() {
    log_info "Configuring HashiCorp services for monitoring..."
    
    # Note: This section would typically involve:
    # 1. Updating Vault configuration to enable enhanced telemetry
    # 2. Configuring Nomad for OTEL integration
    # 3. Setting up Consul Connect for observability
    
    log_warning "HashiCorp service configuration requires manual intervention"
    log_warning "Please refer to the OTEL Integration Guide for detailed instructions"
}

# Create monitoring validation script
create_validation_script() {
    log_info "Creating monitoring validation script..."
    
    cat > "$MONITORING_DIR/scripts/validate-monitoring.sh" <<'EOF'
#!/bin/bash
# Monitoring Stack Validation Script

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "[INFO] $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Test service endpoints
test_endpoints() {
    local endpoints=(
        "Prometheus:http://localhost:9090/-/healthy"
        "Grafana:http://localhost:3000/api/health"
        "Alertmanager:http://localhost:9093/-/healthy"
        "Loki:http://localhost:3100/ready"
    )
    
    for endpoint in "${endpoints[@]}"; do
        IFS=':' read -r name url <<< "$endpoint"
        if curl -s "$url" &> /dev/null; then
            log_success "$name is healthy"
        else
            log_error "$name is not responding"
        fi
    done
}

# Test metric collection
test_metrics() {
    log_info "Testing metric collection..."
    
    # Test Prometheus metrics
    if curl -s "http://localhost:9090/api/v1/query?query=up" | jq -r '.data.result | length' | grep -q '^[1-9]'; then
        log_success "Prometheus is collecting metrics"
    else
        log_error "Prometheus is not collecting metrics"
    fi
}

# Test alerting
test_alerting() {
    log_info "Testing alerting configuration..."
    
    # Check alert rules
    local rules_count
    rules_count=$(curl -s "http://localhost:9090/api/v1/rules" | jq -r '.data.groups | length')
    
    if [[ $rules_count -gt 0 ]]; then
        log_success "Alert rules are loaded ($rules_count groups)"
    else
        log_error "No alert rules found"
    fi
}

# Test log collection
test_logs() {
    log_info "Testing log collection..."
    
    # Test Loki labels
    if curl -s "http://localhost:3100/loki/api/v1/labels" | jq -r '.data | length' | grep -q '^[1-9]'; then
        log_success "Loki is collecting logs"
    else
        log_error "Loki is not collecting logs"
    fi
}

# Main validation
main() {
    log_info "Starting monitoring stack validation..."
    
    test_endpoints
    test_metrics
    test_alerting
    test_logs
    
    log_success "Monitoring validation completed"
}

main "$@"
EOF
    
    chmod +x "$MONITORING_DIR/scripts/validate-monitoring.sh"
    log_success "Validation script created"
}

# Print deployment summary
print_summary() {
    log_success "Monitoring stack deployment completed!"
    
    echo ""
    echo "=== Monitoring Stack URLs ==="
    echo "Grafana:      http://localhost:3000"
    echo "Prometheus:   http://localhost:9090"
    echo "Alertmanager: http://localhost:9093"
    echo "Loki:         http://localhost:3100"
    echo ""
    
    echo "=== Default Credentials ==="
    echo "Grafana: admin / $(grep GRAFANA_ADMIN_PASSWORD "$MONITORING_DIR/.env" | cut -d'=' -f2)"
    echo ""
    
    echo "=== Next Steps ==="
    echo "1. Update secrets in $MONITORING_DIR/.env"
    echo "2. Configure HashiCorp services (see OTEL Integration Guide)"
    echo "3. Run validation: $MONITORING_DIR/scripts/validate-monitoring.sh"
    echo "4. Import additional dashboards as needed"
    echo ""
    
    echo "=== Important Files ==="
    echo "Configuration: $MONITORING_DIR"
    echo "Data:         $DATA_PATH"
    echo "Logs:         /var/log/cloudya/monitoring"
    echo ""
    
    log_warning "Remember to update the placeholder secrets and tokens!"
}

# Main execution
main() {
    log_info "Starting HashiCorp monitoring stack deployment..."
    
    check_prerequisites
    setup_directories
    generate_secrets
    
    setup_prometheus
    setup_grafana
    setup_loki
    setup_alertmanager
    setup_otel
    
    create_network
    deploy_stack
    wait_for_services
    
    # Deploy OTEL to Nomad if available
    if command -v nomad &> /dev/null && curl -s "$NOMAD_ADDR/v1/status/leader" &> /dev/null; then
        deploy_otel_nomad
    else
        log_warning "Nomad not available - OTEL collector deployment skipped"
    fi
    
    configure_hashicorp_monitoring
    create_validation_script
    print_summary
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi