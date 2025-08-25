#!/bin/bash

# Setup Monitoring Infrastructure
# Deploys Prometheus, Grafana, and AlertManager with automation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
ENVIRONMENT="${ENVIRONMENT:-production}"
DOMAIN="${DOMAIN:-cloudya.net}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-$(openssl rand -base64 32)}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[MONITORING]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${YELLOW}[STEP]${NC} $1"; }

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    # Check if Nomad is running
    if ! nomad status >/dev/null 2>&1; then
        log_error "Nomad is not accessible. Monitoring requires Nomad cluster."
        exit 1
    fi
    
    # Check if Vault is available
    if ! vault status >/dev/null 2>&1; then
        log_error "Vault is not accessible. Monitoring setup requires Vault."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Setup monitoring secrets in Vault
setup_monitoring_secrets() {
    log_step "Setting up monitoring secrets in Vault..."
    
    # Enable KV secrets engine for monitoring
    vault secrets enable -path=monitoring kv-v2 2>/dev/null || true
    
    # Store Grafana admin credentials
    vault kv put monitoring/grafana \
        admin_user="admin" \
        admin_password="$GRAFANA_ADMIN_PASSWORD" \
        secret_key="$(openssl rand -hex 32)" \
        created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    # Store Prometheus configuration
    vault kv put monitoring/prometheus \
        retention_time="30d" \
        retention_size="50GB" \
        scrape_interval="15s" \
        evaluation_interval="15s"
    
    # Store AlertManager configuration
    vault kv put monitoring/alertmanager \
        smtp_host="smtp.example.com" \
        smtp_port="587" \
        smtp_user="alerts@$DOMAIN" \
        alert_email_to="admin@$DOMAIN"
    
    log_success "Monitoring secrets configured in Vault"
}

# Create Prometheus configuration
create_prometheus_config() {
    log_step "Creating Prometheus configuration..."
    
    mkdir -p "$INFRA_DIR/monitoring/prometheus/config"
    
    cat > "$INFRA_DIR/monitoring/prometheus/config/prometheus.yml" <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "rules/*.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager.service.consul:9093

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'nomad'
    consul_sd_configs:
      - server: 'consul.service.consul:8500'
        services: ['nomad']
    metrics_path: '/v1/metrics'
    params:
      format: ['prometheus']

  - job_name: 'consul'
    static_configs:
      - targets: ['consul.service.consul:8500']

  - job_name: 'vault'
    scheme: https
    tls_config:
      insecure_skip_verify: true
    consul_sd_configs:
      - server: 'consul.service.consul:8500'
        services: ['vault']
    metrics_path: '/v1/sys/metrics'
    params:
      format: ['prometheus']

  - job_name: 'traefik'
    consul_sd_configs:
      - server: 'consul.service.consul:8500'
        services: ['traefik']
    metrics_path: '/metrics'

  - job_name: 'node-exporter'
    consul_sd_configs:
      - server: 'consul.service.consul:8500'
        services: ['node-exporter']
EOF
    
    log_success "Prometheus configuration created"
}

# Create Grafana dashboards
create_grafana_dashboards() {
    log_step "Creating Grafana dashboards..."
    
    mkdir -p "$INFRA_DIR/monitoring/grafana/dashboards"
    
    # HashiCorp Infrastructure Dashboard
    cat > "$INFRA_DIR/monitoring/grafana/dashboards/hashicorp-infrastructure.json" <<EOF
{
  "dashboard": {
    "id": null,
    "title": "HashiCorp Infrastructure Overview",
    "tags": ["hashicorp", "infrastructure"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Nomad Jobs",
        "type": "stat",
        "targets": [
          {
            "expr": "nomad_nomad_job_summary_running",
            "legendFormat": "Running Jobs"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "Vault Health",
        "type": "stat",
        "targets": [
          {
            "expr": "vault_core_active",
            "legendFormat": "Active Vault"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      },
      {
        "id": 3,
        "title": "Consul Members",
        "type": "stat",
        "targets": [
          {
            "expr": "consul_serf_lan_members",
            "legendFormat": "Consul Members"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8}
      },
      {
        "id": 4,
        "title": "Traefik Requests",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(traefik_requests_total[5m])",
            "legendFormat": "{{method}} {{code}}"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8}
      }
    ],
    "time": {"from": "now-1h", "to": "now"},
    "refresh": "30s"
  }
}
EOF
    
    log_success "Grafana dashboards created"
}

# Create AlertManager rules
create_alert_rules() {
    log_step "Creating alert rules..."
    
    mkdir -p "$INFRA_DIR/monitoring/prometheus/rules"
    
    cat > "$INFRA_DIR/monitoring/prometheus/rules/infrastructure.yml" <<EOF
groups:
  - name: infrastructure
    rules:
      - alert: NomadJobDown
        expr: nomad_nomad_job_summary_running == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Nomad job {{ \$labels.job }} is down"
          description: "Nomad job {{ \$labels.job }} has been down for more than 2 minutes"

      - alert: VaultSealed
        expr: vault_core_unsealed == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Vault is sealed"
          description: "Vault instance {{ \$labels.instance }} is sealed"

      - alert: ConsulLeaderElection
        expr: consul_raft_leader == 0
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Consul leader election in progress"
          description: "Consul cluster is undergoing leader election"

      - alert: TraefikHighErrorRate
        expr: rate(traefik_requests_total{code=~"5.."}[5m]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Traefik high error rate"
          description: "Traefik error rate is {{ \$value }} errors per second"

      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes > 0.85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ \$labels.instance }}"
          description: "Memory usage is above 85% on {{ \$labels.instance }}"

      - alert: HighCPUUsage
        expr: 100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage"
          description: "CPU usage is above 80%"
EOF
    
    log_success "Alert rules created"
}

# Deploy monitoring stack via Nomad
deploy_monitoring_stack() {
    log_step "Deploying monitoring stack via Nomad..."
    
    # Create monitoring namespace
    nomad namespace apply -description "Monitoring infrastructure" monitoring 2>/dev/null || true
    
    # Deploy Prometheus
    cat > /tmp/prometheus.nomad <<EOF
job "prometheus" {
  datacenters = ["dc1"]
  namespace   = "monitoring"
  type        = "service"

  group "prometheus" {
    count = 1

    volume "prometheus-data" {
      type      = "host"
      read_only = false
      source    = "prometheus-data"
    }

    volume "prometheus-config" {
      type      = "host"
      read_only = true
      source    = "prometheus-config"
    }

    network {
      port "prometheus" {
        static = 9090
      }
    }

    service {
      name = "prometheus"
      port = "prometheus"
      
      check {
        type     = "http"
        path     = "/-/healthy"
        interval = "10s"
        timeout  = "3s"
      }
    }

    task "prometheus" {
      driver = "docker"

      volume_mount {
        volume      = "prometheus-data"
        destination = "/prometheus"
        read_only   = false
      }

      volume_mount {
        volume      = "prometheus-config"
        destination = "/etc/prometheus"
        read_only   = true
      }

      config {
        image = "prom/prometheus:latest"
        ports = ["prometheus"]
        args = [
          "--config.file=/etc/prometheus/prometheus.yml",
          "--storage.tsdb.path=/prometheus",
          "--web.console.libraries=/etc/prometheus/console_libraries",
          "--web.console.templates=/etc/prometheus/consoles",
          "--web.enable-lifecycle",
          "--storage.tsdb.retention.time=30d",
          "--storage.tsdb.retention.size=50GB"
        ]
      }

      resources {
        cpu    = 1000
        memory = 2048
      }
    }
  }
}
EOF

    nomad job run /tmp/prometheus.nomad
    
    # Deploy Grafana
    cat > /tmp/grafana.nomad <<EOF
job "grafana" {
  datacenters = ["dc1"]
  namespace   = "monitoring"
  type        = "service"

  group "grafana" {
    count = 1

    volume "grafana-data" {
      type      = "host"
      read_only = false
      source    = "grafana-data"
    }

    network {
      port "grafana" {
        static = 3000
      }
    }

    service {
      name = "grafana"
      port = "grafana"
      
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.grafana.rule=Host(\`grafana.$DOMAIN\`)",
        "traefik.http.routers.grafana.tls.certresolver=letsencrypt"
      ]
      
      check {
        type     = "http"
        path     = "/api/health"
        interval = "10s"
        timeout  = "3s"
      }
    }

    task "grafana" {
      driver = "docker"

      volume_mount {
        volume      = "grafana-data"
        destination = "/var/lib/grafana"
        read_only   = false
      }

      config {
        image = "grafana/grafana:latest"
        ports = ["grafana"]
      }

      env {
        GF_SECURITY_ADMIN_PASSWORD = "$GRAFANA_ADMIN_PASSWORD"
        GF_SERVER_ROOT_URL = "https://grafana.$DOMAIN"
        GF_INSTALL_PLUGINS = "grafana-clock-panel,grafana-simple-json-datasource"
      }

      resources {
        cpu    = 500
        memory = 1024
      }
    }
  }
}
EOF

    nomad job run /tmp/grafana.nomad
    
    log_success "Monitoring stack deployed"
}

# Setup Vault monitoring policy
setup_vault_monitoring_policy() {
    log_step "Setting up Vault monitoring policy..."
    
    cat > /tmp/monitoring-policy.hcl <<EOF
# Monitoring policy for Prometheus and Grafana
path "monitoring/data/*" {
  capabilities = ["read", "list"]
}

path "monitoring/metadata/*" {
  capabilities = ["read", "list"]
}

# Allow reading metrics
path "sys/metrics" {
  capabilities = ["read"]
}

# Allow health checks
path "sys/health" {
  capabilities = ["read"]
}
EOF
    
    vault policy write monitoring /tmp/monitoring-policy.hcl
    
    # Create token for monitoring
    MONITORING_TOKEN=$(vault token create \
        -policy=monitoring \
        -period=24h \
        -format=json | jq -r '.auth.client_token')
    
    vault kv put monitoring/vault token="$MONITORING_TOKEN"
    
    log_success "Vault monitoring policy configured"
}

# Validate monitoring setup
validate_monitoring_setup() {
    log_step "Validating monitoring setup..."
    
    # Check Prometheus
    if curl -s http://localhost:9090/-/healthy >/dev/null; then
        log_success "Prometheus is healthy"
    else
        log_error "Prometheus health check failed"
    fi
    
    # Check Grafana
    if curl -s http://localhost:3000/api/health >/dev/null; then
        log_success "Grafana is healthy"
    else
        log_error "Grafana health check failed"
    fi
    
    # Check service registration
    if nomad job status -namespace=monitoring prometheus >/dev/null 2>&1; then
        log_success "Prometheus job is running"
    else
        log_error "Prometheus job is not running"
    fi
    
    if nomad job status -namespace=monitoring grafana >/dev/null 2>&1; then
        log_success "Grafana job is running"
    else
        log_error "Grafana job is not running"
    fi
}

# Main execution
main() {
    log_info "Setting up monitoring infrastructure for environment: $ENVIRONMENT"
    
    check_prerequisites
    setup_monitoring_secrets
    create_prometheus_config
    create_grafana_dashboards
    create_alert_rules
    setup_vault_monitoring_policy
    deploy_monitoring_stack
    
    # Wait for services to start
    log_info "Waiting for services to start..."
    sleep 30
    
    validate_monitoring_setup
    
    log_success "Monitoring setup completed successfully!"
    log_info "Access URLs:"
    log_info "  - Prometheus: http://localhost:9090"
    log_info "  - Grafana: https://grafana.$DOMAIN (admin/$GRAFANA_ADMIN_PASSWORD)"
    log_info "  - Grafana (local): http://localhost:3000 (admin/$GRAFANA_ADMIN_PASSWORD)"
    
    # Save credentials
    echo "Grafana Admin Password: $GRAFANA_ADMIN_PASSWORD" > /tmp/monitoring-credentials.txt
    chmod 600 /tmp/monitoring-credentials.txt
    log_info "Credentials saved to /tmp/monitoring-credentials.txt"
}

# Run main function
main "$@"