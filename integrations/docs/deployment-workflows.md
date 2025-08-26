# Vault Infrastructure Integration - Deployment Workflows

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Environment Setup](#environment-setup)
- [Deployment Strategies](#deployment-strategies)
- [CI/CD Integration](#cicd-integration)
- [Monitoring and Observability](#monitoring-and-observability)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

## Overview

This document provides comprehensive guidance for deploying applications integrated with the Vault infrastructure, including Vault, Consul, Nomad, and Prometheus services.

### Architecture Overview

```mermaid
graph TB
    subgraph "CI/CD Pipeline"
        A[Source Code] --> B[Build & Test]
        B --> C[Security Scan]
        C --> D[Package]
    end
    
    subgraph "Vault Infrastructure"
        V[Vault] --> |Secrets| APP[Application]
        C[Consul] --> |Service Discovery| APP
        N[Nomad] --> |Orchestration| APP
        P[Prometheus] --> |Monitoring| APP
    end
    
    subgraph "Deployment Flow"
        D --> E[Vault Auth]
        E --> F[Consul Register]
        F --> G[Nomad Deploy]
        G --> H[Health Check]
        H --> I[Monitoring Setup]
    end
```

## Prerequisites

### Required Tools

1. **HashiCorp CLI Tools**
   ```bash
   # Install Vault CLI
   curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
   sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
   sudo apt-get update && sudo apt-get install vault
   
   # Install Consul CLI
   sudo apt-get install consul
   
   # Install Nomad CLI
   sudo apt-get install nomad
   ```

2. **Container Runtime**
   ```bash
   # Docker
   curl -fsSL https://get.docker.com -o get-docker.sh
   sudo sh get-docker.sh
   
   # Add user to docker group
   sudo usermod -aG docker $USER
   ```

3. **Programming Language SDKs**
   ```bash
   # Python SDK
   pip install vault-infrastructure-sdk
   
   # Node.js SDK
   npm install vault-infrastructure-sdk
   ```

### Environment Variables

Create environment configuration files for each environment:

**Production Environment (`.env.production`)**
```bash
# Vault Configuration
VAULT_ADDR=https://vault.production.internal:8200
VAULT_NAMESPACE=root
VAULT_ROLE_ID=your-production-role-id
VAULT_SECRET_ID=your-production-secret-id

# Consul Configuration
CONSUL_HTTP_ADDR=https://consul.production.internal:8500
CONSUL_HTTP_TOKEN=your-consul-token

# Nomad Configuration
NOMAD_ADDR=https://nomad.production.internal:4646
NOMAD_TOKEN=your-nomad-token

# Prometheus Configuration
PROMETHEUS_URL=https://prometheus.production.internal:9090
PROMETHEUS_PUSHGATEWAY=https://pushgateway.production.internal:9091
```

**Staging Environment (`.env.staging`)**
```bash
# Vault Configuration
VAULT_ADDR=https://vault.staging.internal:8200
VAULT_NAMESPACE=root
VAULT_ROLE_ID=your-staging-role-id
VAULT_SECRET_ID=your-staging-secret-id

# Consul Configuration
CONSUL_HTTP_ADDR=https://consul.staging.internal:8500
CONSUL_HTTP_TOKEN=your-consul-token

# Nomad Configuration
NOMAD_ADDR=https://nomad.staging.internal:4646
NOMAD_TOKEN=your-nomad-token

# Prometheus Configuration
PROMETHEUS_URL=https://prometheus.staging.internal:9090
PROMETHEUS_PUSHGATEWAY=https://pushgateway.staging.internal:9091
```

## Environment Setup

### 1. Vault Configuration

#### Create Application Secrets
```bash
# Authenticate with Vault
vault auth -method=userpass username=admin

# Create secrets for different environments
vault kv put secret/applications/my-app/production \
    database_url="postgresql://user:pass@prod-db:5432/myapp" \
    api_key="prod-api-key-12345" \
    encryption_key="32-char-production-key-here!!"

vault kv put secret/applications/my-app/staging \
    database_url="postgresql://user:pass@staging-db:5432/myapp" \
    api_key="staging-api-key-67890" \
    encryption_key="32-char-staging-key-here!!!"
```

#### Setup AppRole Authentication
```bash
# Enable AppRole auth method
vault auth enable approle

# Create policy for application
vault policy write my-app-production - <<EOF
path "secret/data/applications/my-app/production" {
  capabilities = ["read"]
}

path "database/creds/my-app-production" {
  capabilities = ["read"]
}
EOF

# Create AppRole
vault write auth/approle/role/my-app-production \
    token_policies="my-app-production" \
    token_ttl=1h \
    token_max_ttl=24h \
    bind_secret_id=true \
    secret_id_ttl=10m

# Get Role ID and Secret ID
vault read auth/approle/role/my-app-production/role-id
vault write -f auth/approle/role/my-app-production/secret-id
```

### 2. Consul Service Mesh

#### Configure Service Mesh
```bash
# Create service configuration
cat > my-app-service.json << EOF
{
  "service": {
    "name": "my-app",
    "port": 8080,
    "tags": ["web", "api"],
    "check": {
      "http": "http://localhost:8080/health",
      "interval": "10s"
    },
    "connect": {
      "sidecar_service": {}
    }
  }
}
EOF

# Register service
consul services register my-app-service.json
```

#### Setup Service Intentions
```bash
# Allow communication from frontend to my-app
consul intention create frontend my-app

# Allow communication from my-app to database
consul intention create my-app database
```

### 3. Nomad Job Configuration

#### Create Job Specification
```hcl
job "my-app" {
  datacenters = ["dc1"]
  type = "service"
  
  group "app" {
    count = 3
    
    vault {
      policies = ["my-app-production"]
      change_mode = "restart"
    }
    
    service {
      name = "my-app"
      port = "http"
      
      tags = [
        "web",
        "api",
        "version:${var.version}",
        "environment:${var.environment}"
      ]
      
      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "3s"
      }
      
      connect {
        sidecar_service {}
      }
    }
    
    task "app" {
      driver = "docker"
      
      config {
        image = "${var.image}:${var.version}"
        ports = ["http"]
      }
      
      template {
        data = <<EOH
{{ with secret "secret/applications/my-app/production" }}
DATABASE_URL={{ .Data.data.database_url }}
API_KEY={{ .Data.data.api_key }}
ENCRYPTION_KEY={{ .Data.data.encryption_key }}
{{ end }}
        EOH
        destination = "secrets/app.env"
        env = true
        change_mode = "restart"
      }
      
      resources {
        cpu    = 256
        memory = 512
      }
      
      env {
        PORT = "${NOMAD_PORT_http}"
        ENVIRONMENT = "${var.environment}"
      }
    }
    
    network {
      port "http" {
        to = 8080
      }
    }
  }
}

variable "image" {
  type = string
  default = "my-app"
}

variable "version" {
  type = string
  default = "latest"
}

variable "environment" {
  type = string
  default = "production"
}
```

## Deployment Strategies

### 1. Blue-Green Deployment

```bash
#!/bin/bash
# blue-green-deploy.sh

set -e

APP_NAME="my-app"
NEW_VERSION=$1
ENVIRONMENT=${2:-production}

echo "🔄 Starting Blue-Green deployment for ${APP_NAME}:${NEW_VERSION}"

# Step 1: Deploy green version
echo "🟢 Deploying green version..."
nomad job run \
    -var="version=${NEW_VERSION}" \
    -var="environment=${ENVIRONMENT}" \
    -var="color=green" \
    ${APP_NAME}-green.nomad

# Step 2: Wait for green to be healthy
echo "⏳ Waiting for green deployment to be healthy..."
timeout 300 bash -c "
    until nomad job status ${APP_NAME}-green | grep -q 'running'; do
        sleep 10
        echo 'Still waiting for green deployment...'
    done
"

# Step 3: Health check
echo "🏥 Performing health checks on green deployment..."
for i in {1..5}; do
    if curl -f "http://${APP_NAME}-green.${ENVIRONMENT}.internal:8080/health"; then
        echo "✅ Health check $i passed"
    else
        echo "❌ Health check $i failed"
        exit 1
    fi
    sleep 2
done

# Step 4: Switch traffic (update Consul service)
echo "🔄 Switching traffic to green deployment..."
consul kv put "service/${APP_NAME}/active" "green"

# Step 5: Verify traffic switch
echo "🔍 Verifying traffic switch..."
sleep 30

# Step 6: Stop blue deployment
echo "🔵 Stopping blue deployment..."
nomad job stop ${APP_NAME}-blue || true

echo "✅ Blue-Green deployment completed successfully!"
```

### 2. Canary Deployment

```bash
#!/bin/bash
# canary-deploy.sh

set -e

APP_NAME="my-app"
NEW_VERSION=$1
ENVIRONMENT=${2:-production}
CANARY_PERCENTAGE=${3:-10}

echo "🐤 Starting Canary deployment for ${APP_NAME}:${NEW_VERSION}"

# Step 1: Deploy canary version with reduced count
echo "🚀 Deploying canary version..."
CANARY_COUNT=$(nomad job status ${APP_NAME} | grep "Desired" | awk '{print $2}' | head -1)
CANARY_COUNT=$((CANARY_COUNT * CANARY_PERCENTAGE / 100))

nomad job run \
    -var="version=${NEW_VERSION}" \
    -var="environment=${ENVIRONMENT}" \
    -var="count=${CANARY_COUNT}" \
    -var="canary=true" \
    ${APP_NAME}-canary.nomad

# Step 2: Monitor canary metrics
echo "📊 Monitoring canary metrics for 10 minutes..."
CANARY_START_TIME=$(date +%s)
MONITORING_DURATION=600  # 10 minutes

while [ $(($(date +%s) - CANARY_START_TIME)) -lt $MONITORING_DURATION ]; do
    # Check error rate
    ERROR_RATE=$(curl -s "http://prometheus:9090/api/v1/query?query=rate(http_requests_total{job='${APP_NAME}',version='${NEW_VERSION}',status=~'5..'}[5m])" | jq '.data.result[0].value[1] // 0' | tr -d '"')
    
    if (( $(echo "$ERROR_RATE > 0.05" | bc -l) )); then
        echo "❌ High error rate detected: $ERROR_RATE"
        echo "🔄 Rolling back canary deployment..."
        nomad job stop ${APP_NAME}-canary
        exit 1
    fi
    
    echo "✅ Canary metrics look good. Error rate: $ERROR_RATE"
    sleep 60
done

# Step 3: Promote canary to full deployment
echo "🎉 Promoting canary to full deployment..."
nomad job run \
    -var="version=${NEW_VERSION}" \
    -var="environment=${ENVIRONMENT}" \
    ${APP_NAME}.nomad

echo "✅ Canary deployment completed successfully!"
```

### 3. Rolling Deployment

```bash
#!/bin/bash
# rolling-deploy.sh

set -e

APP_NAME="my-app"
NEW_VERSION=$1
ENVIRONMENT=${2:-production}

echo "🔄 Starting Rolling deployment for ${APP_NAME}:${NEW_VERSION}"

# Update job specification with rolling update strategy
cat > ${APP_NAME}-rolling.nomad << EOF
job "${APP_NAME}" {
  datacenters = ["dc1"]
  type = "service"
  
  update {
    max_parallel     = 2
    min_healthy_time = "30s"
    healthy_deadline = "3m"
    progress_deadline = "10m"
    auto_revert      = true
    canary           = 0
    stagger          = "10s"
  }
  
  group "app" {
    count = 6
    
    task "app" {
      driver = "docker"
      
      config {
        image = "${var.image}:${NEW_VERSION}"
        ports = ["http"]
      }
      
      # ... rest of configuration
    }
  }
}
EOF

# Deploy with rolling update
nomad job run ${APP_NAME}-rolling.nomad

echo "✅ Rolling deployment started. Monitor with: nomad job status ${APP_NAME}"
```

## CI/CD Integration

### GitHub Actions Integration

```yaml
# Example workflow step for deployment
- name: Deploy to Nomad
  env:
    NOMAD_ADDR: ${{ secrets.NOMAD_ADDR }}
    NOMAD_TOKEN: ${{ secrets.NOMAD_TOKEN }}
    VAULT_ADDR: ${{ secrets.VAULT_ADDR }}
    VAULT_ROLE_ID: ${{ secrets.VAULT_ROLE_ID }}
    VAULT_SECRET_ID: ${{ secrets.VAULT_SECRET_ID }}
  run: |
    # Authenticate with Vault
    export VAULT_TOKEN=$(vault write -field=token auth/approle/login \
      role_id="$VAULT_ROLE_ID" \
      secret_id="$VAULT_SECRET_ID")
    
    # Deploy application
    ./scripts/deploy.sh ${{ github.sha }} production
```

### GitLab CI Integration

```yaml
deploy:
  stage: deploy
  script:
    - ./scripts/vault-integration-deploy.sh $CI_COMMIT_SHA $ENVIRONMENT
  environment:
    name: $ENVIRONMENT
    url: https://my-app.$ENVIRONMENT.internal
```

### Jenkins Integration

```groovy
stage('Deploy') {
    withVault([
        configuration: [vaultUrl: env.VAULT_ADDR, vaultCredentialId: 'vault-approle'],
        vaultSecrets: [
            [path: 'secret/infrastructure/tokens', secretValues: [
                [envVar: 'NOMAD_TOKEN', vaultKey: 'nomad_token']
            ]]
        ]
    ]) {
        sh './scripts/deploy.sh ${BUILD_NUMBER} ${ENVIRONMENT}'
    }
}
```

## Monitoring and Observability

### Prometheus Metrics

#### Application Metrics
```python
# Python application metrics
from prometheus_client import Counter, Histogram, Gauge, start_http_server

REQUEST_COUNT = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
REQUEST_LATENCY = Histogram('http_request_duration_seconds', 'HTTP request latency')
ACTIVE_CONNECTIONS = Gauge('active_connections', 'Active connections')

@REQUEST_LATENCY.time()
def handle_request():
    # Your request handling code
    REQUEST_COUNT.labels(method='GET', endpoint='/api/users', status=200).inc()
```

#### Infrastructure Metrics
```bash
# Push deployment metrics
curl -X POST http://prometheus-pushgateway:9091/metrics/job/deployment/instance/my-app \
  --data-binary @- << EOF
# TYPE deployment_info gauge
deployment_info{version="v1.2.3",environment="production"} 1
# TYPE deployment_timestamp gauge  
deployment_timestamp $(date +%s)
EOF
```

### Grafana Dashboards

Create monitoring dashboards with key metrics:

1. **Application Performance**
   - Request rate and latency
   - Error rates
   - Database connection pool status

2. **Infrastructure Health**
   - Nomad job status
   - Consul service health
   - Vault seal status

3. **Business Metrics**
   - User registrations
   - Transaction volume
   - Feature usage

### Alerting Rules

```yaml
# alerts.yml
groups:
- name: application.rules
  rules:
  - alert: HighErrorRate
    expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.05
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: High error rate detected
      description: Error rate is {{ $value }} for {{ $labels.job }}

  - alert: ServiceDown
    expr: up{job="my-app"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: Service is down
      description: "{{ $labels.job }} has been down for more than 1 minute"
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Vault Authentication Failures

**Problem**: `permission denied` errors when accessing secrets

**Solution**:
```bash
# Check token status
vault token lookup

# Verify policy permissions
vault policy read my-app-policy

# Test secret access
vault kv get secret/applications/my-app/production
```

#### 2. Consul Service Registration Issues

**Problem**: Services not appearing in Consul catalog

**Solution**:
```bash
# Check Consul agent logs
consul monitor

# Verify service definition
consul services list
consul catalog services

# Test service registration manually
consul services register service.json
```

#### 3. Nomad Deployment Failures

**Problem**: Jobs failing to start or becoming unhealthy

**Solution**:
```bash
# Check job status
nomad job status my-app

# View allocation logs
nomad alloc logs <allocation-id>

# Check resource constraints
nomad node status
nomad job plan my-app.nomad
```

#### 4. Secret Template Rendering Issues

**Problem**: Vault templates not rendering in Nomad jobs

**Solution**:
```bash
# Check Vault agent logs in allocation
nomad alloc logs <allocation-id> vault

# Verify template syntax
nomad job validate my-app.nomad

# Test secret access manually
vault kv get secret/applications/my-app/production
```

### Debugging Commands

```bash
# Vault debugging
export VAULT_LOG_LEVEL=debug
vault status -detailed

# Consul debugging  
export CONSUL_LOG_LEVEL=debug
consul members -detailed

# Nomad debugging
export NOMAD_LOG_LEVEL=debug
nomad status -verbose
```

## Best Practices

### Security Best Practices

1. **Least Privilege Access**
   - Create minimal Vault policies
   - Use short-lived tokens
   - Rotate secrets regularly

2. **Network Security**
   - Use TLS for all communications
   - Implement network segmentation
   - Use Consul Connect for service mesh

3. **Secret Management**
   - Never commit secrets to version control
   - Use Vault dynamic secrets when possible
   - Implement secret rotation

### Deployment Best Practices

1. **Progressive Rollouts**
   - Always use canary or blue-green deployments for production
   - Implement automated rollback triggers
   - Monitor key metrics during deployments

2. **Health Checks**
   - Implement comprehensive health checks
   - Use different check types (HTTP, TCP, script)
   - Set appropriate timeouts and intervals

3. **Resource Management**
   - Set resource limits and requests
   - Use auto-scaling when appropriate
   - Monitor resource usage

### Monitoring Best Practices

1. **Golden Signals**
   - Monitor latency, traffic, errors, and saturation
   - Set up alerting for critical metrics
   - Use SLOs and SLIs

2. **Observability**
   - Implement distributed tracing
   - Use structured logging
   - Create meaningful dashboards

3. **Incident Response**
   - Have clear escalation procedures
   - Maintain runbooks for common issues
   - Practice incident response regularly

## Example Deployment Scripts

See the `/scripts` directory for complete deployment automation scripts:

- `deploy-full-stack.sh` - Complete application deployment
- `vault-setup.sh` - Vault configuration automation
- `consul-mesh-setup.sh` - Service mesh configuration
- `monitoring-setup.sh` - Prometheus and Grafana setup
- `rollback.sh` - Automated rollback procedures

## Support and Documentation

- **Internal Documentation**: Check the `/docs` directory for additional guides
- **Monitoring**: Access Grafana dashboards at https://grafana.internal
- **Issue Tracking**: Report issues through your ticketing system
- **Emergency Procedures**: See the incident response runbook