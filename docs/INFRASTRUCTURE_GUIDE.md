# Infrastructure Documentation - Vault, Nomad, Consul & Traefik

## 📋 Table of Contents

- [Architecture Overview](#architecture-overview)
- [Quick Start Guide](#quick-start-guide)
- [Component Guides](#component-guides)
  - [HashiCorp Vault](#hashicorp-vault)
  - [HashiCorp Nomad](#hashicorp-nomad)
  - [HashiCorp Consul](#hashicorp-consul)
  - [Traefik Proxy](#traefik-proxy)
- [Integration Guides](#integration-guides)
- [Security Best Practices](#security-best-practices)
- [Monitoring Setup](#monitoring-setup)
- [Scaling Strategies](#scaling-strategies)
- [CI/CD Integration](#cicd-integration)
- [Troubleshooting](#troubleshooting)
- [Automation Scripts](#automation-scripts)

## 🏗️ Architecture Overview

### System Architecture

This infrastructure provides a production-ready, scalable platform using HashiCorp's stack with Traefik as the reverse proxy:

```mermaid
graph TB
    Internet[Internet] --> Traefik[Traefik Proxy]
    Traefik --> Vault[HashiCorp Vault]
    Traefik --> Nomad[HashiCorp Nomad]
    Traefik --> Consul[HashiCorp Consul]
    Traefik --> Apps[Applications]
    
    Consul --> ServiceDiscovery[Service Discovery]
    Vault --> Secrets[Secret Management]
    Nomad --> WorkloadOrchestration[Workload Orchestration]
    
    Apps --> Database[(Database)]
    Apps --> Storage[(Storage)]
    
    subgraph "Monitoring Stack"
        Prometheus[Prometheus]
        Grafana[Grafana]
        Loki[Loki]
        AlertManager[Alert Manager]
    end
    
    Apps --> Prometheus
    Vault --> Prometheus
    Nomad --> Prometheus
    Consul --> Prometheus
    Traefik --> Prometheus
```

### Core Components

| Component | Role | Port | Purpose |
|-----------|------|------|---------|
| **Traefik** | Reverse Proxy | 80, 443 | Load balancing, SSL termination, routing |
| **Vault** | Secret Management | 8200, 8201 | Credential storage, encryption, PKI |
| **Nomad** | Orchestration | 4646, 4647, 4648 | Container/application scheduling |
| **Consul** | Service Discovery | 8500, 8501, 8502 | Service mesh, configuration, health checks |
| **Prometheus** | Monitoring | 9090 | Metrics collection and alerting |
| **Grafana** | Visualization | 3000 | Dashboards and analytics |

### Network Flow

1. **External Traffic** → Traefik (SSL termination, routing)
2. **Service Discovery** → Consul (health checks, service registration)
3. **Secret Management** → Vault (credentials, certificates)
4. **Workload Scheduling** → Nomad (container orchestration)
5. **Monitoring** → Prometheus/Grafana (metrics, alerting)

## 🚀 Quick Start Guide

### Prerequisites

- Docker and Docker Compose
- Git
- OpenSSL (for certificate generation)
- Linux/macOS environment with bash

### Local Development Setup

1. **Clone and Setup**:
   ```bash
   git clone https://github.com/your-org/cloudya-vault.git
   cd cloudya-vault/infrastructure
   cp config/local.env.template local.env
   ```

2. **Start Local Stack**:
   ```bash
   make local-up
   # or
   docker-compose -f docker-compose.local.yml --env-file local.env up -d
   ```

3. **Initialize Vault**:
   ```bash
   ./scripts/init-vault.sh
   ```

4. **Access Services**:
   - Traefik Dashboard: http://localhost:8080
   - Vault UI: http://localhost:8200 (use provided root token)
   - Nomad UI: http://localhost:4646
   - Consul UI: http://localhost:8500
   - Grafana: http://localhost:3000 (admin/admin)

### Production Deployment

1. **Server Provisioning**:
   ```bash
   ./scripts/provision-server.sh root@your-server.com --verbose
   ```

2. **Environment Configuration**:
   ```bash
   cp config/production.env.template production.env
   # Edit with your values
   ```

3. **Deploy Infrastructure**:
   ```bash
   ./scripts/remote-deploy.sh --verbose
   ```

## 📦 Component Guides

### HashiCorp Vault

Vault serves as the centralized secret management system, providing secure storage, dynamic secrets, and encryption services.

#### Key Features

- **Secret Storage**: KV store for application secrets
- **Dynamic Secrets**: Database credentials with automatic rotation
- **PKI**: Certificate authority for internal TLS
- **Encryption as a Service**: Data encryption/decryption
- **Auth Methods**: Multiple authentication backends

#### Configuration

**Basic Vault Configuration** (`vault.hcl`):

```hcl
ui = true
disable_mlock = false

storage "raft" {
  path = "/var/lib/vault"
  node_id = "vault-1"
  retry_join {
    auto_join = "provider=consul"
    auto_join_scheme = "https"
  }
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = false
  tls_cert_file = "/etc/vault.d/tls/vault-cert.pem"
  tls_key_file  = "/etc/vault.d/tls/vault-key.pem"
  tls_ca_file   = "/etc/vault.d/tls/ca-cert.pem"
  tls_min_version = "tls12"
}

api_addr = "https://vault.yourcompany.com:8200"
cluster_addr = "https://vault.yourcompany.com:8201"

telemetry {
  prometheus_retention_time = "30s"
  disable_hostname = true
}
```

#### Common Operations

**Initialize Vault**:
```bash
vault operator init -key-shares=5 -key-threshold=3
```

**Unseal Vault**:
```bash
vault operator unseal <key1>
vault operator unseal <key2>
vault operator unseal <key3>
```

**Enable Auth Methods**:
```bash
vault auth enable userpass
vault auth enable approle
vault auth enable kubernetes
```

**Create Policies**:
```bash
vault policy write app-policy - <<EOF
path "secret/data/app/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
```

**Mount Secret Engines**:
```bash
vault secrets enable -path=secret kv-v2
vault secrets enable database
vault secrets enable pki
```

### HashiCorp Nomad

Nomad handles workload orchestration, scheduling containers and applications across your infrastructure.

#### Key Features

- **Multi-Workload Support**: Containers, VMs, static binaries
- **Flexible Scheduling**: Constraints, affinities, spread
- **Service Discovery**: Consul integration
- **Secrets Integration**: Vault integration
- **Rolling Deployments**: Blue/green, canary deployments

#### Configuration

**Server Configuration** (`nomad-server.hcl`):

```hcl
datacenter = "dc1"
data_dir   = "/opt/nomad/data"
log_level  = "INFO"

server {
  enabled          = true
  bootstrap_expect = 3
  raft_protocol    = 3
}

acl = {
  enabled = true
}

consul {
  address             = "127.0.0.1:8500"
  auto_advertise      = true
  server_auto_join    = true
  client_auto_join    = true
}

vault {
  enabled = true
  address = "https://vault.yourcompany.com:8200"
}

telemetry {
  collection_interval = "1s"
  disable_hostname    = true
  prometheus_metrics  = true
  publish_allocation_metrics = true
  publish_node_metrics = true
}
```

**Client Configuration** (`nomad-client.hcl`):

```hcl
datacenter = "dc1"
data_dir   = "/opt/nomad/data"
log_level  = "INFO"

client {
  enabled = true
  
  servers = [
    "nomad-server-1.internal:4647",
    "nomad-server-2.internal:4647",
    "nomad-server-3.internal:4647"
  ]
  
  node_class = "compute"
  
  meta {
    "instance_type" = "m5.large"
    "availability_zone" = "us-west-2a"
  }
}

plugin "docker" {
  config {
    allow_privileged = false
    volumes {
      enabled = true
    }
  }
}
```

#### Job Specifications

**Web Application Job**:

```hcl
job "webapp" {
  region      = "global"
  datacenters = ["dc1"]
  type        = "service"

  group "web" {
    count = 3

    network {
      port "http" {
        to = 8080
      }
    }

    service {
      name = "webapp"
      port = "http"
      
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.webapp.rule=Host(`app.yourcompany.com`)",
        "traefik.http.routers.webapp.tls=true"
      ]

      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "3s"
      }
    }

    task "webapp" {
      driver = "docker"
      
      config {
        image = "nginx:alpine"
        ports = ["http"]
      }

      vault {
        policies = ["webapp-policy"]
      }

      template {
        data = <<EOF
{{- with secret "secret/data/webapp" -}}
DATABASE_URL={{ .Data.data.database_url }}
API_KEY={{ .Data.data.api_key }}
{{- end -}}
EOF
        destination = "secrets/app.env"
        env = true
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
```

### HashiCorp Consul

Consul provides service discovery, configuration management, and service mesh capabilities.

#### Key Features

- **Service Discovery**: Automatic service registration and discovery
- **Health Checking**: Application and service health monitoring
- **Key/Value Store**: Distributed configuration management
- **Service Mesh**: Secure service-to-service communication
- **Multi-Datacenter**: Cross-datacenter replication

#### Configuration

**Server Configuration** (`consul.hcl`):

```hcl
datacenter = "dc1"
data_dir = "/opt/consul/data"
log_level = "INFO"
server = true
bootstrap_expect = 3

retry_join = [
  "consul-server-1.internal",
  "consul-server-2.internal",
  "consul-server-3.internal"
]

ui_config {
  enabled = true
}

connect {
  enabled = true
}

acl = {
  enabled = true
  default_policy = "deny"
  enable_token_persistence = true
}

performance {
  raft_multiplier = 1
}

telemetry {
  prometheus_retention_time = "30s"
  disable_hostname = true
}

ports {
  grpc = 8502
}
```

#### Service Registration

**Service Definition**:

```json
{
  "service": {
    "name": "webapp",
    "tags": ["web", "production"],
    "port": 8080,
    "check": {
      "http": "http://localhost:8080/health",
      "interval": "10s"
    }
  }
}
```

**DNS Query Example**:
```bash
dig @consul.service.consul webapp.service.consul
```

### Traefik Proxy

Traefik serves as the edge router, handling SSL termination, load balancing, and routing.

#### Key Features

- **Automatic Service Discovery**: Consul backend integration
- **SSL Management**: Let's Encrypt integration
- **Load Balancing**: Multiple algorithms
- **Middleware**: Authentication, rate limiting, compression
- **Monitoring**: Prometheus metrics, access logs

#### Configuration

**Main Configuration** (`traefik.yml`):

```yaml
global:
  checkNewVersion: false
  sendAnonymousUsage: false

api:
  dashboard: true
  insecure: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entrypoint:
          to: websecure
          scheme: https
          permanent: true

  websecure:
    address: ":443"

certificatesResolvers:
  letsencrypt:
    acme:
      tlsChallenge: {}
      email: admin@yourcompany.com
      storage: /data/acme.json
      caServer: https://acme-v02.api.letsencrypt.org/directory

providers:
  consul:
    rootKey: "traefik"
    endpoints:
      - "consul.service.consul:8500"

  consulCatalog:
    prefix: traefik
    exposedByDefault: false
    endpoints:
      - "consul.service.consul:8500"

metrics:
  prometheus:
    addEntryPointsLabels: true
    addServicesLabels: true

log:
  level: INFO
  format: json

accessLog:
  format: json
```

**Dynamic Configuration** (`dynamic.yml`):

```yaml
http:
  middlewares:
    default-headers:
      headers:
        frameDeny: true
        sslRedirect: true
        browserXssFilter: true
        contentTypeNosniff: true
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 31536000
        
    secure-headers:
      headers:
        accessControlAllowMethods:
          - GET
          - OPTIONS
          - PUT
        accessControlMaxAge: 100
        hostsProxyHeaders:
          - "X-Forwarded-Host"

    auth:
      basicAuth:
        users:
          - "admin:$2y$10$..."

tls:
  options:
    default:
      sslProtocols:
        - "TLSv1.2"
        - "TLSv1.3"
      cipherSuites:
        - "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
        - "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305"
        - "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
```

## 🔗 Integration Guides

### Vault-Nomad Integration

Enable Nomad to fetch secrets from Vault automatically:

**1. Configure Vault Policy**:
```bash
vault policy write nomad-server - <<EOF
path "auth/token/create/nomad-cluster" {
  capabilities = ["update"]
}
path "auth/token/revoke-accessor" {
  capabilities = ["update"]
}
path "auth/token/roles/nomad-cluster" {
  capabilities = ["read"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
path "auth/token/lookup" {
  capabilities = ["update"]
}
path "auth/token/revoke-accessor" {
  capabilities = ["update"]
}
path "sys/capabilities-self" {
  capabilities = ["update"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF
```

**2. Create Token Role**:
```bash
vault write auth/token/roles/nomad-cluster @- <<EOF
{
  "allowed_policies": "access-tables",
  "explicit_max_ttl": 0,
  "name": "nomad-cluster",
  "orphan": true,
  "period": 259200,
  "renewable": true
}
EOF
```

**3. Generate Token**:
```bash
vault token create -policy nomad-server -period 72h -orphan
```

### Consul-Traefik Integration

Configure Traefik to discover services through Consul:

**1. Service Definition with Traefik Tags**:
```json
{
  "service": {
    "name": "webapp",
    "port": 8080,
    "tags": [
      "traefik.enable=true",
      "traefik.http.routers.webapp.rule=Host(`app.example.com`)",
      "traefik.http.routers.webapp.tls=true",
      "traefik.http.routers.webapp.tls.certresolver=letsencrypt"
    ]
  }
}
```

**2. Health Check Configuration**:
```json
{
  "check": {
    "http": "http://localhost:8080/health",
    "interval": "10s",
    "timeout": "3s"
  }
}
```

### Application Integration Examples

#### Python Flask Application

```python
import hvac
import consul
from flask import Flask

app = Flask(__name__)

# Vault client setup
vault_client = hvac.Client(url='https://vault.example.com:8200')
vault_client.token = os.environ['VAULT_TOKEN']

# Consul client setup
consul_client = consul.Consul(host='consul.example.com')

@app.route('/health')
def health_check():
    return {'status': 'healthy'}, 200

@app.route('/config')
def get_config():
    # Fetch secret from Vault
    secret = vault_client.secrets.kv.v2.read_secret_version(
        path='app/config'
    )
    
    # Register service with Consul
    consul_client.agent.service.register(
        name='flask-app',
        service_id='flask-app-1',
        port=5000,
        check=consul.Check.http('http://localhost:5000/health', interval='10s')
    )
    
    return secret['data']['data']

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
```

#### Node.js Express Application

```javascript
const express = require('express');
const vault = require('node-vault');
const consul = require('consul');

const app = express();
const port = 3000;

// Initialize Vault client
const vaultClient = vault({
  endpoint: 'https://vault.example.com:8200',
  token: process.env.VAULT_TOKEN
});

// Initialize Consul client
const consulClient = consul({
  host: 'consul.example.com'
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

// Configuration endpoint
app.get('/config', async (req, res) => {
  try {
    // Fetch secret from Vault
    const secret = await vaultClient.read('secret/data/app/config');
    
    // Register service with Consul
    await consulClient.agent.service.register({
      name: 'node-app',
      id: 'node-app-1',
      port: port,
      check: {
        http: `http://localhost:${port}/health`,
        interval: '10s'
      }
    });
    
    res.json(secret.data.data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});
```

## 🔒 Security Best Practices

### Infrastructure Security

#### 1. Network Security

**Firewall Rules**:
```bash
# Allow SSH
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Allow HTTP/HTTPS
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# HashiCorp services (internal only)
iptables -A INPUT -p tcp --dport 8200 -s 10.0.0.0/8 -j ACCEPT  # Vault
iptables -A INPUT -p tcp --dport 4646 -s 10.0.0.0/8 -j ACCEPT  # Nomad
iptables -A INPUT -p tcp --dport 8500 -s 10.0.0.0/8 -j ACCEPT  # Consul

# Default deny
iptables -P INPUT DROP
```

**VPC Security Groups** (AWS):
```yaml
SecurityGroups:
  WebTierSG:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Web tier security group
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 80
          ToPort: 80
          CidrIp: 0.0.0.0/0
        - IpProtocol: tcp
          FromPort: 443
          ToPort: 443
          CidrIp: 0.0.0.0/0
          
  AppTierSG:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Application tier security group
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 8200
          ToPort: 8200
          SourceSecurityGroupId: !Ref WebTierSG
        - IpProtocol: tcp
          FromPort: 4646
          ToPort: 4646
          SourceSecurityGroupId: !Ref WebTierSG
```

#### 2. TLS/SSL Configuration

**Generate CA Certificate**:
```bash
# Generate CA private key
openssl genrsa -out ca-key.pem 4096

# Generate CA certificate
openssl req -new -x509 -days 365 -key ca-key.pem -sha256 -out ca-cert.pem -subj "/C=US/ST=CA/L=San Francisco/O=YourOrg/CN=Internal CA"
```

**Generate Service Certificates**:
```bash
# Generate service private key
openssl genrsa -out vault-key.pem 4096

# Create certificate signing request
openssl req -subj "/CN=vault.example.com" -sha256 -new -key vault-key.pem -out vault.csr

# Sign certificate with CA
openssl x509 -req -days 365 -sha256 -in vault.csr -CA ca-cert.pem -CAkey ca-key.pem -out vault-cert.pem -extensions v3_req -extfile <(
cat <<EOF
[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = vault.example.com
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF
)
```

#### 3. Vault Security

**ACL Policies**:
```hcl
# Developer policy
path "secret/data/dev/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/data/production/*" {
  capabilities = ["deny"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}
```

**AppRole Authentication**:
```bash
# Enable AppRole
vault auth enable approle

# Create role
vault write auth/approle/role/webapp \
    token_policies="webapp-policy" \
    token_ttl=1h \
    token_max_ttl=4h \
    bind_secret_id=true

# Get role ID
vault read auth/approle/role/webapp/role-id

# Generate secret ID
vault write -f auth/approle/role/webapp/secret-id
```

#### 4. Secrets Management

**Dynamic Database Credentials**:
```bash
# Enable database secrets engine
vault secrets enable database

# Configure database connection
vault write database/config/postgres \
    plugin_name=postgresql-database-plugin \
    connection_url="postgresql://{{username}}:{{password}}@postgres:5432/app?sslmode=require" \
    allowed_roles="readonly,readwrite" \
    username="vault-admin" \
    password="secure-password"

# Create role
vault write database/roles/readonly \
    db_name=postgres \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h"
```

**PKI Certificate Management**:
```bash
# Enable PKI secrets engine
vault secrets enable pki
vault secrets tune -max-lease-ttl=8760h pki

# Generate root CA
vault write pki/root/generate/internal \
    common_name="Internal CA" \
    ttl=8760h

# Configure PKI URLs
vault write pki/config/urls \
    issuing_certificates="https://vault.example.com:8200/v1/pki/ca" \
    crl_distribution_points="https://vault.example.com:8200/v1/pki/crl"

# Create role
vault write pki/roles/example-dot-com \
    allowed_domains="example.com" \
    allow_subdomains=true \
    max_ttl="720h"
```

### Security Monitoring

**Vault Audit Logging**:
```bash
# Enable file audit
vault audit enable file file_path=/var/log/vault/audit.log

# Enable syslog audit
vault audit enable syslog
```

**Security Scanning Script**:
```bash
#!/bin/bash
# security-scan.sh

echo "=== Security Scan Report ==="
echo "Timestamp: $(date)"

# Check for unencrypted communications
echo "Checking for unencrypted traffic..."
netstat -tlnp | grep -E ":(8500|8200|4646)" | grep -v "127.0.0.1"

# Check file permissions
echo "Checking sensitive file permissions..."
find /etc/vault.d -type f -exec ls -la {} \;
find /etc/consul.d -type f -exec ls -la {} \;
find /etc/nomad.d -type f -exec ls -la {} \;

# Check for default passwords
echo "Checking for default credentials..."
vault status
consul info
nomad status

# Check certificate expiration
echo "Checking certificate expiration..."
openssl x509 -in /etc/vault.d/tls/vault-cert.pem -noout -dates
openssl x509 -in /etc/consul.d/tls/consul-cert.pem -noout -dates

echo "=== End Security Scan ==="
```

## 📊 Monitoring Setup

### Prometheus Configuration

**Prometheus Configuration** (`prometheus.yml`):

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'production'
    region: 'us-west-2'

rule_files:
  - "/etc/prometheus/rules/*.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

scrape_configs:
  # Vault metrics
  - job_name: 'vault'
    static_configs:
      - targets: ['vault:8200']
    metrics_path: '/v1/sys/metrics'
    params:
      format: ['prometheus']
    bearer_token: 'vault-prometheus-token'

  # Nomad metrics
  - job_name: 'nomad'
    consul_sd_configs:
      - server: 'consul:8500'
        services: ['nomad']
    relabel_configs:
      - source_labels: [__meta_consul_service_port]
        regex: '4646'
        action: keep

  # Consul metrics
  - job_name: 'consul'
    static_configs:
      - targets: ['consul:8500']
    metrics_path: '/v1/agent/metrics'
    params:
      format: ['prometheus']

  # Traefik metrics
  - job_name: 'traefik'
    static_configs:
      - targets: ['traefik:8080']

  # Node Exporter
  - job_name: 'node'
    consul_sd_configs:
      - server: 'consul:8500'
        services: ['node-exporter']

  # Application metrics
  - job_name: 'applications'
    consul_sd_configs:
      - server: 'consul:8500'
        services: ['webapp', 'api']
    relabel_configs:
      - source_labels: [__meta_consul_service_metadata_metrics_path]
        target_label: __metrics_path__
        regex: (.+)
```

### Alert Rules

**HashiCorp Services Alerts** (`hashicorp-alerts.yml`):

```yaml
groups:
  - name: vault
    rules:
      - alert: VaultDown
        expr: up{job="vault"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Vault instance is down"
          description: "Vault instance {{ $labels.instance }} has been down for more than 1 minute."

      - alert: VaultSealed
        expr: vault_core_unsealed == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Vault is sealed"
          description: "Vault instance {{ $labels.instance }} is sealed."

      - alert: VaultHighRequestLatency
        expr: vault_core_handle_request{quantile="0.99"} > 1000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Vault high request latency"
          description: "Vault 99th percentile latency is {{ $value }}ms"

  - name: nomad
    rules:
      - alert: NomadDown
        expr: up{job="nomad"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Nomad instance is down"

      - alert: NomadJobFailed
        expr: nomad_nomad_job_summary_failed > 0
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Nomad job has failed allocations"
          description: "Job {{ $labels.job }} has {{ $value }} failed allocations"

      - alert: NomadHighResourceUtilization
        expr: nomad_client_allocated_cpu > 80
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Nomad node high CPU utilization"

  - name: consul
    rules:
      - alert: ConsulDown
        expr: up{job="consul"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Consul instance is down"

      - alert: ConsulLeaderElection
        expr: increase(consul_raft_leader_elections_total[1h]) > 0
        for: 0m
        labels:
          severity: warning
        annotations:
          summary: "Consul leader election occurred"

      - alert: ConsulServiceUnhealthy
        expr: consul_health_service_status{status!="passing"} > 0
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Consul service unhealthy"
          description: "Service {{ $labels.service_name }} is unhealthy"
```

### Grafana Dashboards

**Vault Dashboard JSON** (excerpt):

```json
{
  "dashboard": {
    "title": "HashiCorp Vault",
    "panels": [
      {
        "title": "Vault Status",
        "type": "stat",
        "targets": [
          {
            "expr": "vault_core_unsealed",
            "legendFormat": "Unsealed"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {
              "mode": "thresholds"
            },
            "thresholds": {
              "steps": [
                {
                  "color": "red",
                  "value": 0
                },
                {
                  "color": "green",
                  "value": 1
                }
              ]
            }
          }
        }
      },
      {
        "title": "Request Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(vault_core_handle_request_count[5m])",
            "legendFormat": "Requests/sec"
          }
        ]
      },
      {
        "title": "Response Times",
        "type": "graph",
        "targets": [
          {
            "expr": "vault_core_handle_request{quantile=\"0.50\"}",
            "legendFormat": "50th percentile"
          },
          {
            "expr": "vault_core_handle_request{quantile=\"0.95\"}",
            "legendFormat": "95th percentile"
          },
          {
            "expr": "vault_core_handle_request{quantile=\"0.99\"}",
            "legendFormat": "99th percentile"
          }
        ]
      }
    ]
  }
}
```

### Log Management

**Loki Configuration** (`loki-config.yaml`):

```yaml
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 168h

storage_config:
  boltdb:
    directory: /loki/index
  filesystem:
    directory: /loki/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: true
  retention_period: 720h
```

**Promtail Configuration** (`promtail-config.yaml`):

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: vault
    static_configs:
      - targets:
          - localhost
        labels:
          job: vault
          service: vault
          __path__: /var/log/vault/*.log

  - job_name: nomad
    static_configs:
      - targets:
          - localhost
        labels:
          job: nomad
          service: nomad
          __path__: /var/log/nomad/*.log

  - job_name: consul
    static_configs:
      - targets:
          - localhost
        labels:
          job: consul
          service: consul
          __path__: /var/log/consul/*.log

  - job_name: traefik
    static_configs:
      - targets:
          - localhost
        labels:
          job: traefik
          service: traefik
          __path__: /var/log/traefik/*.log
```

## 🚀 Scaling Strategies

### Horizontal Scaling

#### 1. Multi-Node Setup

**Vault Cluster**:
```hcl
storage "raft" {
  path = "/var/lib/vault"
  node_id = "vault-{{ node_id }}"
  
  retry_join {
    leader_api_addr = "https://vault-1.internal:8200"
  }
  retry_join {
    leader_api_addr = "https://vault-2.internal:8200"
  }
  retry_join {
    leader_api_addr = "https://vault-3.internal:8200"
  }
}

cluster_addr = "https://{{ local_ip }}:8201"
api_addr = "https://{{ local_ip }}:8200"
```

**Nomad Cluster**:
```hcl
server {
  enabled = true
  bootstrap_expect = 3
  
  server_join {
    retry_join = [
      "nomad-1.internal",
      "nomad-2.internal", 
      "nomad-3.internal"
    ]
    retry_max = 3
    retry_interval = "15s"
  }
}
```

**Consul Cluster**:
```hcl
bootstrap_expect = 3
retry_join = [
  "consul-1.internal",
  "consul-2.internal",
  "consul-3.internal"
]

performance {
  raft_multiplier = 1
}
```

#### 2. Auto Scaling Groups (AWS)

**Auto Scaling Group Configuration**:
```yaml
Resources:
  NomadClientASG:
    Type: AWS::AutoScaling::AutoScalingGroup
    Properties:
      VPCZoneIdentifier: 
        - !Ref PrivateSubnet1
        - !Ref PrivateSubnet2
      LaunchConfigurationName: !Ref NomadClientLC
      MinSize: 2
      MaxSize: 10
      DesiredCapacity: 3
      HealthCheckType: ELB
      HealthCheckGracePeriod: 300
      Tags:
        - Key: Name
          Value: nomad-client
          PropagateAtLaunch: true

  NomadClientScaleUpPolicy:
    Type: AWS::AutoScaling::ScalingPolicy
    Properties:
      AutoScalingGroupName: !Ref NomadClientASG
      PolicyType: TargetTrackingScaling
      TargetTrackingConfiguration:
        PredefinedMetricSpecification:
          PredefinedMetricType: ASGAverageCPUUtilization
        TargetValue: 70.0
```

### Vertical Scaling

#### 1. Resource Allocation

**Nomad Job Resource Scaling**:
```hcl
job "webapp" {
  group "app" {
    scaling {
      enabled = true
      min = 1
      max = 10
      
      policy {
        evaluation_interval = "30s"
        cooldown = "1m"
        
        check "avg_cpu" {
          source = "prometheus"
          query = "avg(nomad_client_allocs_cpu_total_percent{job=\"webapp\"})"
          
          strategy "target-value" {
            target = 70
          }
        }
      }
    }
    
    task "web" {
      resources {
        cpu = 500    # Can be increased
        memory = 512  # Can be increased
      }
    }
  }
}
```

#### 2. Performance Optimization

**Vault Performance Tuning**:
```hcl
storage "raft" {
  path = "/var/lib/vault"
  
  # Performance tuning
  performance_multiplier = 5
  snapshot_threshold = 16384
  trailing_logs = 10000
}

# Increase file descriptor limits
ulimit {
  nofile = 65536
}

# Tune cache size
cache {
  size = "1024MB"
}
```

**Nomad Performance Tuning**:
```hcl
client {
  # Increase GC settings
  gc_interval = "1m"
  gc_parallel_destroys = 4
  gc_disk_usage_threshold = 80
  gc_inode_usage_threshold = 80
  
  # Increase max parallel downloads
  artifact {
    http_read_timeout = "30m"
    http_max_bytes = "100MB"
  }
  
  # Tune resource allocation
  reserved {
    cpu = 100
    memory = 256
    disk = 1000
  }
}
```

### Database Scaling

**Vault Database Scaling**:
```bash
# Enable database secrets engine with multiple connections
vault secrets enable database

# Configure read replica
vault write database/config/postgres-read \
    plugin_name=postgresql-database-plugin \
    connection_url="postgresql://{{username}}:{{password}}@postgres-read:5432/app" \
    allowed_roles="readonly" \
    username="vault-read" \
    password="secure-password"

# Configure write primary
vault write database/config/postgres-write \
    plugin_name=postgresql-database-plugin \
    connection_url="postgresql://{{username}}:{{password}}@postgres-write:5432/app" \
    allowed_roles="readwrite" \
    username="vault-write" \
    password="secure-password"
```

### Load Balancing

**Traefik Load Balancer Configuration**:
```yaml
http:
  services:
    vault-backend:
      loadBalancer:
        servers:
          - url: "https://vault-1.internal:8200"
          - url: "https://vault-2.internal:8200"
          - url: "https://vault-3.internal:8200"
        healthCheck:
          path: /v1/sys/health
          interval: 30s
          timeout: 5s
        
    nomad-backend:
      loadBalancer:
        servers:
          - url: "http://nomad-1.internal:4646"
          - url: "http://nomad-2.internal:4646"
          - url: "http://nomad-3.internal:4646"
        sticky:
          cookie:
            name: nomad-server
            secure: true
            httpOnly: true
```

## 🔄 CI/CD Integration

### GitHub Actions

**Vault Secrets Integration**:

```yaml
name: Deploy Application

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Vault
        uses: hashicorp/vault-action@v2
        with:
          url: https://vault.example.com:8200
          method: approle
          roleId: ${{ secrets.VAULT_ROLE_ID }}
          secretId: ${{ secrets.VAULT_SECRET_ID }}
          secrets: |
            secret/data/app database_url | DATABASE_URL ;
            secret/data/app api_key | API_KEY
            
      - name: Deploy to Nomad
        run: |
          # Update job spec with new image
          sed -i 's|IMAGE_TAG|${{ github.sha }}|g' deploy/app.nomad
          
          # Deploy job
          nomad job run deploy/app.nomad
          
        env:
          NOMAD_ADDR: https://nomad.example.com:4646
          NOMAD_TOKEN: ${{ secrets.NOMAD_TOKEN }}
```

**Complete CI/CD Pipeline**:

```yaml
name: Full CI/CD Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

env:
  VAULT_ADDR: https://vault.example.com:8200
  NOMAD_ADDR: https://nomad.example.com:4646
  CONSUL_HTTP_ADDR: https://consul.example.com:8500

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'
          
      - name: Install dependencies
        run: npm ci
        
      - name: Run tests
        run: npm test
        
      - name: Run integration tests
        run: npm run test:integration
        env:
          DATABASE_URL: postgresql://test:test@localhost:5432/test

  security-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Run security scan
        uses: securecodewarrior/github-action-add-sarif@v1
        with:
          sarif-file: security-scan-results.sarif
          
      - name: Vault security audit
        run: |
          vault audit list
          vault policy list

  build:
    needs: [test, security-scan]
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Docker Buildx
        uses: docker/setup-buildx-action@v2
        
      - name: Login to Registry
        uses: docker/login-action@v2
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
          
      - name: Build and push
        uses: docker/build-push-action@v4
        with:
          push: true
          tags: ghcr.io/example/app:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  deploy-staging:
    if: github.ref == 'refs/heads/develop'
    needs: build
    runs-on: ubuntu-latest
    environment: staging
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Get secrets from Vault
        uses: hashicorp/vault-action@v2
        with:
          url: ${{ env.VAULT_ADDR }}
          method: approle
          roleId: ${{ secrets.VAULT_ROLE_ID }}
          secretId: ${{ secrets.VAULT_SECRET_ID }}
          secrets: |
            secret/data/staging/nomad token | NOMAD_TOKEN
            
      - name: Deploy to staging
        run: |
          # Update job specification
          envsubst < deploy/staging.nomad.tpl > deploy/staging.nomad
          
          # Deploy to Nomad
          nomad job run deploy/staging.nomad
          
          # Register with Consul
          consul services register deploy/staging-service.json
          
        env:
          IMAGE_TAG: ${{ github.sha }}
          ENVIRONMENT: staging

  deploy-production:
    if: github.ref == 'refs/heads/main'
    needs: build
    runs-on: ubuntu-latest
    environment: production
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Get secrets from Vault
        uses: hashicorp/vault-action@v2
        with:
          url: ${{ env.VAULT_ADDR }}
          method: approle
          roleId: ${{ secrets.VAULT_ROLE_ID }}
          secretId: ${{ secrets.VAULT_SECRET_ID }}
          secrets: |
            secret/data/production/nomad token | NOMAD_TOKEN
            secret/data/production/database url | DATABASE_URL
            secret/data/production/app api_key | API_KEY
            
      - name: Deploy to production
        run: |
          # Blue-green deployment
          envsubst < deploy/production.nomad.tpl > deploy/production.nomad
          
          # Deploy new version
          nomad job run deploy/production.nomad
          
          # Health check
          ./scripts/health-check.sh
          
          # Update Consul tags for traffic switching
          consul kv put app/version ${{ github.sha }}
          
        env:
          IMAGE_TAG: ${{ github.sha }}
          ENVIRONMENT: production
          
      - name: Post-deployment tests
        run: |
          ./scripts/smoke-tests.sh
          ./scripts/performance-tests.sh
```

### Jenkins Pipeline

**Jenkinsfile**:

```groovy
pipeline {
    agent any
    
    environment {
        VAULT_ADDR = 'https://vault.example.com:8200'
        NOMAD_ADDR = 'https://nomad.example.com:4646'
        CONSUL_HTTP_ADDR = 'https://consul.example.com:8500'
        DOCKER_REGISTRY = 'registry.example.com'
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Test') {
            parallel {
                stage('Unit Tests') {
                    steps {
                        sh 'npm test'
                    }
                }
                
                stage('Security Scan') {
                    steps {
                        sh './scripts/security-scan.sh'
                    }
                }
                
                stage('Lint') {
                    steps {
                        sh 'npm run lint'
                    }
                }
            }
        }
        
        stage('Build') {
            steps {
                script {
                    def image = docker.build("${DOCKER_REGISTRY}/app:${env.BUILD_NUMBER}")
                    image.push()
                    image.push("latest")
                }
            }
        }
        
        stage('Get Secrets') {
            steps {
                withCredentials([
                    string(credentialsId: 'vault-role-id', variable: 'ROLE_ID'),
                    string(credentialsId: 'vault-secret-id', variable: 'SECRET_ID')
                ]) {
                    sh '''
                        # Authenticate with Vault
                        VAULT_TOKEN=$(vault write -field=token auth/approle/login \
                            role_id=${ROLE_ID} \
                            secret_id=${SECRET_ID})
                        
                        # Get deployment secrets
                        vault kv get -field=nomad_token secret/deploy > nomad_token
                        vault kv get -field=consul_token secret/deploy > consul_token
                    '''
                }
            }
        }
        
        stage('Deploy to Staging') {
            when {
                branch 'develop'
            }
            steps {
                sh '''
                    export NOMAD_TOKEN=$(cat nomad_token)
                    export CONSUL_HTTP_TOKEN=$(cat consul_token)
                    
                    # Update job specification
                    sed "s|IMAGE_TAG|${BUILD_NUMBER}|g" deploy/staging.nomad.tpl > staging.nomad
                    
                    # Deploy to Nomad
                    nomad job run staging.nomad
                    
                    # Wait for deployment
                    nomad job status webapp-staging
                '''
            }
        }
        
        stage('Deploy to Production') {
            when {
                branch 'main'
            }
            steps {
                input message: 'Deploy to production?', ok: 'Deploy'
                
                sh '''
                    export NOMAD_TOKEN=$(cat nomad_token)
                    export CONSUL_HTTP_TOKEN=$(cat consul_token)
                    
                    # Blue-green deployment
                    sed "s|IMAGE_TAG|${BUILD_NUMBER}|g" deploy/production.nomad.tpl > production.nomad
                    
                    # Deploy new version
                    nomad job run production.nomad
                    
                    # Health check
                    ./scripts/health-check.sh
                    
                    # Update load balancer
                    consul kv put app/active-version ${BUILD_NUMBER}
                '''
            }
        }
        
        stage('Post-Deploy Tests') {
            when {
                branch 'main'
            }
            steps {
                sh '''
                    ./scripts/smoke-tests.sh
                    ./scripts/integration-tests.sh
                '''
            }
        }
    }
    
    post {
        always {
            // Clean up secrets
            sh 'rm -f nomad_token consul_token'
            
            // Archive artifacts
            archiveArtifacts artifacts: 'deploy/*.nomad', allowEmptyArchive: true
        }
        
        success {
            slackSend channel: '#deployments',
                     color: 'good',
                     message: "Deployment successful: ${env.JOB_NAME} - ${env.BUILD_NUMBER}"
        }
        
        failure {
            slackSend channel: '#deployments',
                     color: 'danger',
                     message: "Deployment failed: ${env.JOB_NAME} - ${env.BUILD_NUMBER}"
        }
    }
}
```

### GitLab CI/CD

**.gitlab-ci.yml**:

```yaml
variables:
  VAULT_ADDR: https://vault.example.com:8200
  NOMAD_ADDR: https://nomad.example.com:4646
  CONSUL_HTTP_ADDR: https://consul.example.com:8500
  DOCKER_REGISTRY: registry.gitlab.com/example/app

stages:
  - test
  - build
  - deploy-staging
  - deploy-production

.vault-auth: &vault-auth
  before_script:
    - apk add --no-cache curl
    - |
      VAULT_TOKEN=$(curl -s -X POST \
        -d "{\"role_id\":\"${VAULT_ROLE_ID}\",\"secret_id\":\"${VAULT_SECRET_ID}\"}" \
        ${VAULT_ADDR}/v1/auth/approle/login | jq -r .auth.client_token)
      export VAULT_TOKEN

test:
  stage: test
  image: node:18-alpine
  script:
    - npm ci
    - npm test
    - npm run lint
  coverage: '/Statements\s*:\s*([^%]+)/'
  artifacts:
    reports:
      junit: junit.xml
      coverage_report:
        coverage_format: cobertura
        path: coverage/cobertura-coverage.xml

security-scan:
  stage: test
  image: securecodewarrior/gitlab-sca:latest
  script:
    - sca-scan .
  artifacts:
    reports:
      sast: gl-sast-report.json

build:
  stage: build
  image: docker:20.10.16
  services:
    - docker:20.10.16-dind
  script:
    - echo $CI_REGISTRY_PASSWORD | docker login -u $CI_REGISTRY_USER --password-stdin $CI_REGISTRY
    - docker build -t $DOCKER_REGISTRY:$CI_COMMIT_SHA .
    - docker push $DOCKER_REGISTRY:$CI_COMMIT_SHA
    - docker tag $DOCKER_REGISTRY:$CI_COMMIT_SHA $DOCKER_REGISTRY:latest
    - docker push $DOCKER_REGISTRY:latest

deploy-staging:
  stage: deploy-staging
  image: alpine:latest
  <<: *vault-auth
  script:
    - apk add --no-cache gettext nomad consul-template
    - |
      # Get deployment credentials
      NOMAD_TOKEN=$(vault kv get -field=token secret/staging/nomad)
      export NOMAD_TOKEN
      
      # Template job specification
      envsubst < deploy/staging.nomad.tpl > staging.nomad
      
      # Deploy to Nomad
      nomad job run staging.nomad
      
      # Wait for deployment
      nomad job status webapp-staging
  environment:
    name: staging
    url: https://staging.example.com
  only:
    - develop

deploy-production:
  stage: deploy-production
  image: alpine:latest
  <<: *vault-auth
  script:
    - apk add --no-cache gettext nomad consul
    - |
      # Get deployment credentials
      NOMAD_TOKEN=$(vault kv get -field=token secret/production/nomad)
      CONSUL_HTTP_TOKEN=$(vault kv get -field=token secret/production/consul)
      export NOMAD_TOKEN CONSUL_HTTP_TOKEN
      
      # Blue-green deployment
      envsubst < deploy/production.nomad.tpl > production.nomad
      
      # Deploy new version
      nomad job run production.nomad
      
      # Health check
      ./scripts/health-check.sh
      
      # Switch traffic
      consul kv put app/version $CI_COMMIT_SHA
  environment:
    name: production
    url: https://example.com
  when: manual
  only:
    - main
```

## 🔧 Troubleshooting

### Common Issues and Solutions

#### 1. Vault Issues

**Problem**: Vault is sealed
```bash
# Check status
vault status

# Unseal with keys
vault operator unseal <key1>
vault operator unseal <key2>
vault operator unseal <key3>

# Check if unsealed
vault status
```

**Problem**: Token expired
```bash
# Renew token
vault token renew

# Create new token
vault token create -policy=myapp-policy

# Revoke old tokens
vault token revoke <token-id>
```

**Problem**: Permission denied
```bash
# Check current token capabilities
vault token capabilities secret/data/app

# List policies
vault policy list

# Check policy contents
vault policy read myapp-policy
```

#### 2. Nomad Issues

**Problem**: Job fails to start
```bash
# Check job status
nomad job status webapp

# Check allocation status
nomad alloc status <alloc-id>

# Check logs
nomad alloc logs <alloc-id>

# Check events
nomad alloc status -verbose <alloc-id>
```

**Problem**: Service not discoverable
```bash
# Check Consul registration
consul catalog services
consul health service webapp

# Check Nomad service registration
nomad job inspect webapp | jq .Job.TaskGroups[0].Services
```

**Problem**: Resource constraints
```bash
# Check node status
nomad node status

# Check resource usage
nomad node status -verbose <node-id>

# Drain node
nomad node drain -enable <node-id>
```

#### 3. Consul Issues

**Problem**: Service health checks failing
```bash
# Check service health
consul health service webapp

# Check agent logs
journalctl -u consul -f

# Reload configuration
consul reload
```

**Problem**: Leader election issues
```bash
# Check cluster status
consul operator raft list-peers

# Check for split brain
consul members

# Force leave dead node
consul force-leave <node-name>
```

#### 4. Traefik Issues

**Problem**: SSL certificate issues
```bash
# Check certificate status
openssl x509 -in /data/acme.json -text -noout

# Force certificate renewal
rm /data/acme.json
# Restart Traefik

# Check Let's Encrypt limits
curl -s https://acme-v02.api.letsencrypt.org/directory
```

**Problem**: Service not routing
```bash
# Check Traefik configuration
curl -s http://traefik:8080/api/http/services

# Check Consul catalog
consul catalog services

# Verify service tags
consul catalog service webapp
```

### Diagnostic Scripts

**Health Check Script** (`health-check.sh`):
```bash
#!/bin/bash

echo "=== Infrastructure Health Check ==="

# Check Vault
echo "Checking Vault..."
if vault status &> /dev/null; then
    echo "✓ Vault is available and unsealed"
else
    echo "✗ Vault is not available or sealed"
fi

# Check Nomad
echo "Checking Nomad..."
if nomad node status &> /dev/null; then
    echo "✓ Nomad is available"
    NODES=$(nomad node status -quiet | wc -l)
    echo "  - Nodes: $NODES"
else
    echo "✗ Nomad is not available"
fi

# Check Consul
echo "Checking Consul..."
if consul info &> /dev/null; then
    echo "✓ Consul is available"
    SERVICES=$(consul catalog services | wc -l)
    echo "  - Services: $SERVICES"
else
    echo "✗ Consul is not available"
fi

# Check Traefik
echo "Checking Traefik..."
if curl -s http://localhost:8080/api/overview &> /dev/null; then
    echo "✓ Traefik is available"
else
    echo "✗ Traefik is not available"
fi

# Check connectivity between services
echo "Checking service connectivity..."
if consul catalog service webapp &> /dev/null; then
    echo "✓ Services are registered in Consul"
else
    echo "✗ No services found in Consul"
fi

echo "=== Health Check Complete ==="
```

**Log Collector Script** (`collect-logs.sh`):
```bash
#!/bin/bash

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="logs_$TIMESTAMP"

mkdir -p $LOG_DIR

echo "Collecting logs..."

# System logs
journalctl -u vault -n 1000 > $LOG_DIR/vault.log
journalctl -u nomad -n 1000 > $LOG_DIR/nomad.log
journalctl -u consul -n 1000 > $LOG_DIR/consul.log

# Docker logs
docker logs traefik > $LOG_DIR/traefik.log 2>&1
docker logs prometheus > $LOG_DIR/prometheus.log 2>&1
docker logs grafana > $LOG_DIR/grafana.log 2>&1

# Configuration files
cp /etc/vault.d/vault.hcl $LOG_DIR/
cp /etc/nomad.d/nomad.hcl $LOG_DIR/
cp /etc/consul.d/consul.hcl $LOG_DIR/

# Status outputs
vault status > $LOG_DIR/vault-status.txt 2>&1
nomad node status > $LOG_DIR/nomad-status.txt 2>&1
consul members > $LOG_DIR/consul-status.txt 2>&1

# Create archive
tar -czf logs_$TIMESTAMP.tar.gz $LOG_DIR

echo "Logs collected in logs_$TIMESTAMP.tar.gz"
```

## 🤖 Automation Scripts

### Deployment Scripts

The infrastructure includes several automation scripts for managing the deployment lifecycle:

#### 1. Server Provisioning (`scripts/provision-server.sh`)

```bash
#!/bin/bash
# Server provisioning script with security hardening

SERVER=$1
VERBOSE=${VERBOSE:-false}
DRY_RUN=${DRY_RUN:-false}
FORCE=${FORCE:-false}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        *)
            SERVER=$1
            shift
            ;;
    esac
done

if [[ -z "$SERVER" ]]; then
    echo "Usage: $0 <server> [options]"
    echo "Options:"
    echo "  -v, --verbose    Enable verbose output"
    echo "  -d, --dry-run    Preview changes only"
    echo "  -f, --force      Skip confirmation prompts"
    exit 1
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

run_command() {
    local cmd=$1
    local description=$2
    
    log "$description"
    
    if [[ "$VERBOSE" == "true" ]]; then
        echo "Executing: $cmd"
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        ssh -o StrictHostKeyChecking=no $SERVER "$cmd"
    else
        echo "[DRY RUN] Would execute: $cmd"
    fi
}

# Main provisioning logic
main() {
    log "Starting server provisioning for $SERVER"
    
    if [[ "$FORCE" == "false" ]] && [[ "$DRY_RUN" == "false" ]]; then
        read -p "Provision server $SERVER? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Update system
    run_command "apt-get update && apt-get upgrade -y" "Updating system packages"
    
    # Install Docker
    run_command "curl -fsSL https://get.docker.com | sh" "Installing Docker"
    run_command "usermod -aG docker ubuntu" "Adding user to docker group"
    
    # Install HashiCorp tools
    run_command "curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -" "Adding HashiCorp GPG key"
    run_command "apt-add-repository \"deb [arch=amd64] https://apt.releases.hashicorp.com \$(lsb_release -cs) main\"" "Adding HashiCorp repository"
    run_command "apt-get update && apt-get install -y vault nomad consul" "Installing HashiCorp tools"
    
    # Security hardening
    run_command "ufw --force enable" "Enabling firewall"
    run_command "ufw allow 22" "Allowing SSH"
    run_command "ufw allow 80" "Allowing HTTP"
    run_command "ufw allow 443" "Allowing HTTPS"
    
    # Setup directories
    run_command "mkdir -p /etc/{vault.d,nomad.d,consul.d}" "Creating configuration directories"
    run_command "mkdir -p /var/lib/{vault,nomad,consul}" "Creating data directories"
    run_command "mkdir -p /var/log/{vault,nomad,consul}" "Creating log directories"
    
    # Set permissions
    run_command "chown vault:vault /var/lib/vault /var/log/vault" "Setting Vault permissions"
    run_command "chown nomad:nomad /var/lib/nomad /var/log/nomad" "Setting Nomad permissions"
    run_command "chown consul:consul /var/lib/consul /var/log/consul" "Setting Consul permissions"
    
    log "Server provisioning completed for $SERVER"
}

main
```

#### 2. Remote Deployment (`scripts/remote-deploy.sh`)

```bash
#!/bin/bash
# Remote deployment script with rollback capabilities

set -euo pipefail

# Configuration
REMOTE_SERVER=${REMOTE_SERVER:-"cloudya.net"}
REMOTE_USER=${REMOTE_USER:-"root"}
DEPLOYMENT_PATH=${DEPLOYMENT_PATH:-"/opt/cloudya"}
BACKUP_PATH=${BACKUP_PATH:-"/opt/backups"}
VERBOSE=${VERBOSE:-false}
DRY_RUN=${DRY_RUN:-false}
FORCE_DEPLOY=${FORCE_DEPLOY:-false}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)
            echo -e "${GREEN}[INFO]${NC} [$timestamp] $message"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} [$timestamp] $message"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} [$timestamp] $message"
            ;;
        DEBUG)
            if [[ "$VERBOSE" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} [$timestamp] $message"
            fi
            ;;
    esac
}

remote_command() {
    local cmd="$1"
    local description="${2:-Executing remote command}"
    
    log DEBUG "$description: $cmd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would execute on $REMOTE_SERVER: $cmd"
        return 0
    fi
    
    ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_SERVER" "$cmd"
}

check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if we can connect to the server
    if ! ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_SERVER" "echo 'Connection successful'" > /dev/null 2>&1; then
        log ERROR "Cannot connect to $REMOTE_SERVER"
        exit 1
    fi
    
    # Check if required files exist
    local required_files=(
        "docker-compose.production.yml"
        "config/production.env.template"
        "scripts/bootstrap.sh"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log ERROR "Required file not found: $file"
            exit 1
        fi
    done
    
    log INFO "Prerequisites check passed"
}

create_backup() {
    log INFO "Creating backup of current deployment..."
    
    local backup_name="backup_$(date +%Y%m%d_%H%M%S)"
    
    remote_command "mkdir -p $BACKUP_PATH/$backup_name" "Creating backup directory"
    
    # Backup configurations and data
    remote_command "cp -r $DEPLOYMENT_PATH/* $BACKUP_PATH/$backup_name/ 2>/dev/null || true" "Backing up deployment"
    
    # Backup Docker volumes
    remote_command "docker run --rm -v vault_data:/data -v $BACKUP_PATH/$backup_name:/backup alpine tar czf /backup/vault_data.tar.gz -C /data ." "Backing up Vault data"
    remote_command "docker run --rm -v nomad_data:/data -v $BACKUP_PATH/$backup_name:/backup alpine tar czf /backup/nomad_data.tar.gz -C /data ." "Backing up Nomad data"
    remote_command "docker run --rm -v consul_data:/data -v $BACKUP_PATH/$backup_name:/backup alpine tar czf /backup/consul_data.tar.gz -C /data ." "Backing up Consul data"
    
    echo "$backup_name" > .last_backup
    log INFO "Backup created: $backup_name"
}

deploy_files() {
    log INFO "Deploying files to remote server..."
    
    # Create deployment directory
    remote_command "mkdir -p $DEPLOYMENT_PATH" "Creating deployment directory"
    
    # Sync files
    log DEBUG "Syncing files with rsync"
    rsync -avz --delete \
        --exclude='.git' \
        --exclude='node_modules' \
        --exclude='*.log' \
        --exclude='.env' \
        ./ "$REMOTE_USER@$REMOTE_SERVER:$DEPLOYMENT_PATH/"
    
    # Set permissions
    remote_command "chmod +x $DEPLOYMENT_PATH/scripts/*.sh" "Setting script permissions"
    
    log INFO "Files deployed successfully"
}

configure_environment() {
    log INFO "Configuring environment..."
    
    # Check if production.env exists, if not copy from template
    if ! remote_command "test -f $DEPLOYMENT_PATH/production.env"; then
        remote_command "cp $DEPLOYMENT_PATH/config/production.env.template $DEPLOYMENT_PATH/production.env" "Creating production environment file"
        log WARN "Please edit $DEPLOYMENT_PATH/production.env with your configuration"
    fi
    
    # Generate SSL certificates if needed
    remote_command "cd $DEPLOYMENT_PATH && ./scripts/setup-ssl-certificates.sh" "Setting up SSL certificates"
    
    log INFO "Environment configured"
}

deploy_services() {
    log INFO "Deploying services..."
    
    # Stop existing services gracefully
    remote_command "cd $DEPLOYMENT_PATH && docker-compose -f docker-compose.production.yml --env-file production.env down" "Stopping existing services"
    
    # Pull latest images
    remote_command "cd $DEPLOYMENT_PATH && docker-compose -f docker-compose.production.yml --env-file production.env pull" "Pulling latest images"
    
    # Start services
    remote_command "cd $DEPLOYMENT_PATH && docker-compose -f docker-compose.production.yml --env-file production.env up -d" "Starting services"
    
    # Wait for services to be ready
    sleep 30
    
    log INFO "Services deployed"
}

validate_deployment() {
    log INFO "Validating deployment..."
    
    # Check service health
    local services=("vault" "nomad" "consul" "traefik")
    local failed_services=()
    
    for service in "${services[@]}"; do
        if ! remote_command "docker-compose -f $DEPLOYMENT_PATH/docker-compose.production.yml ps | grep $service | grep -q 'Up'"; then
            failed_services+=("$service")
        fi
    done
    
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        log ERROR "Service validation failed for: ${failed_services[*]}"
        return 1
    fi
    
    # Run health checks
    remote_command "cd $DEPLOYMENT_PATH && ./scripts/validate-deployment.sh" "Running health checks"
    
    log INFO "Deployment validation passed"
}

rollback_deployment() {
    log WARN "Rolling back deployment..."
    
    if [[ -f .last_backup ]]; then
        local backup_name=$(cat .last_backup)
        log INFO "Rolling back to backup: $backup_name"
        
        # Stop current services
        remote_command "cd $DEPLOYMENT_PATH && docker-compose -f docker-compose.production.yml down" "Stopping current services"
        
        # Restore from backup
        remote_command "cp -r $BACKUP_PATH/$backup_name/* $DEPLOYMENT_PATH/" "Restoring files from backup"
        
        # Restore Docker volumes
        remote_command "docker run --rm -v vault_data:/data -v $BACKUP_PATH/$backup_name:/backup alpine tar xzf /backup/vault_data.tar.gz -C /data" "Restoring Vault data"
        remote_command "docker run --rm -v nomad_data:/data -v $BACKUP_PATH/$backup_name:/backup alpine tar xzf /backup/nomad_data.tar.gz -C /data" "Restoring Nomad data"
        remote_command "docker run --rm -v consul_data:/data -v $BACKUP_PATH/$backup_name:/backup alpine tar xzf /backup/consul_data.tar.gz -C /data" "Restoring Consul data"
        
        # Start services
        remote_command "cd $DEPLOYMENT_PATH && docker-compose -f docker-compose.production.yml --env-file production.env up -d" "Starting services"
        
        log INFO "Rollback completed"
    else
        log ERROR "No backup found for rollback"
        exit 1
    fi
}

main() {
    log INFO "Starting deployment to $REMOTE_SERVER"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE_DEPLOY=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [options]"
                echo "Options:"
                echo "  -v, --verbose     Enable verbose output"
                echo "  -d, --dry-run     Preview changes only"
                echo "  -f, --force       Skip confirmation prompts"
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Confirmation
    if [[ "$FORCE_DEPLOY" == "false" ]] && [[ "$DRY_RUN" == "false" ]]; then
        read -p "Deploy to production server $REMOTE_SERVER? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log INFO "Deployment cancelled"
            exit 0
        fi
    fi
    
    # Execute deployment steps
    check_prerequisites
    create_backup
    deploy_files
    configure_environment
    deploy_services
    
    if validate_deployment; then
        log INFO "Deployment completed successfully!"
    else
        log ERROR "Deployment validation failed"
        if [[ "$FORCE_DEPLOY" == "false" ]]; then
            read -p "Rollback deployment? (Y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                rollback_deployment
            fi
        fi
        exit 1
    fi
}

# Trap to handle rollback on failure
trap 'log ERROR "Deployment failed"; if [[ "$FORCE_DEPLOY" == "false" ]]; then rollback_deployment; fi' ERR

main "$@"
```

#### 3. Backup and Restore (`scripts/backup-restore.sh`)

```bash
#!/bin/bash
# Comprehensive backup and restore script

set -euo pipefail

BACKUP_DIR=${BACKUP_DIR:-"/opt/backups"}
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="infrastructure_backup_$TIMESTAMP"
RETENTION_DAYS=${RETENTION_DAYS:-30}
ENCRYPTION_KEY=${ENCRYPTION_KEY:-""}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

create_backup() {
    local backup_path="$BACKUP_DIR/$BACKUP_NAME"
    
    log "Creating infrastructure backup: $BACKUP_NAME"
    mkdir -p "$backup_path"
    
    # Backup Vault data
    log "Backing up Vault data..."
    if docker ps | grep -q vault; then
        docker exec vault vault operator raft snapshot save /tmp/vault-snapshot.snap
        docker cp vault:/tmp/vault-snapshot.snap "$backup_path/"
    fi
    
    # Backup Nomad data
    log "Backing up Nomad data..."
    if docker ps | grep -q nomad; then
        docker run --rm \
            -v nomad_data:/data \
            -v "$backup_path:/backup" \
            alpine tar czf /backup/nomad_data.tar.gz -C /data .
    fi
    
    # Backup Consul data
    log "Backing up Consul data..."
    if docker ps | grep -q consul; then
        docker exec consul consul snapshot save /tmp/consul-snapshot.snap
        docker cp consul:/tmp/consul-snapshot.snap "$backup_path/"
        
        # Backup KV store
        docker exec consul consul kv export > "$backup_path/consul-kv.json"
    fi
    
    # Backup configurations
    log "Backing up configurations..."
    cp -r /etc/vault.d "$backup_path/" 2>/dev/null || true
    cp -r /etc/nomad.d "$backup_path/" 2>/dev/null || true
    cp -r /etc/consul.d "$backup_path/" 2>/dev/null || true
    
    # Backup certificates
    log "Backing up certificates..."
    cp -r /etc/ssl/private "$backup_path/ssl_private/" 2>/dev/null || true
    cp -r /etc/ssl/certs "$backup_path/ssl_certs/" 2>/dev/null || true
    
    # Backup environment files
    cp *.env "$backup_path/" 2>/dev/null || true
    
    # Create manifest
    cat > "$backup_path/manifest.json" <<EOF
{
  "backup_name": "$BACKUP_NAME",
  "timestamp": "$TIMESTAMP",
  "created_at": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "services": {
    "vault": $(docker ps | grep -q vault && echo "true" || echo "false"),
    "nomad": $(docker ps | grep -q nomad && echo "true" || echo "false"),
    "consul": $(docker ps | grep -q consul && echo "true" || echo "false"),
    "traefik": $(docker ps | grep -q traefik && echo "true" || echo "false")
  }
}
EOF
    
    # Encrypt backup if key is provided
    if [[ -n "$ENCRYPTION_KEY" ]]; then
        log "Encrypting backup..."
        tar czf - -C "$BACKUP_DIR" "$BACKUP_NAME" | \
        openssl enc -aes-256-cbc -salt -k "$ENCRYPTION_KEY" > "$backup_path.tar.gz.enc"
        rm -rf "$backup_path"
        log "Encrypted backup created: $backup_path.tar.gz.enc"
    else
        # Create compressed archive
        tar czf "$backup_path.tar.gz" -C "$BACKUP_DIR" "$BACKUP_NAME"
        rm -rf "$backup_path"
        log "Backup created: $backup_path.tar.gz"
    fi
}

restore_backup() {
    local backup_file="$1"
    local restore_dir="/tmp/restore_$$"
    
    if [[ ! -f "$backup_file" ]]; then
        log "Backup file not found: $backup_file"
        exit 1
    fi
    
    log "Restoring from backup: $backup_file"
    mkdir -p "$restore_dir"
    
    # Decrypt and extract backup
    if [[ "$backup_file" == *.enc ]]; then
        if [[ -z "$ENCRYPTION_KEY" ]]; then
            log "Encryption key required for encrypted backup"
            exit 1
        fi
        openssl enc -aes-256-cbc -d -salt -k "$ENCRYPTION_KEY" -in "$backup_file" | \
        tar xzf - -C "$restore_dir"
    else
        tar xzf "$backup_file" -C "$restore_dir"
    fi
    
    local backup_dir=$(ls "$restore_dir" | head -1)
    local backup_path="$restore_dir/$backup_dir"
    
    # Read manifest
    if [[ -f "$backup_path/manifest.json" ]]; then
        log "Backup manifest:"
        cat "$backup_path/manifest.json"
    fi
    
    # Confirm restoration
    read -p "Restore this backup? This will overwrite current data (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Restore cancelled"
        rm -rf "$restore_dir"
        exit 0
    fi
    
    # Stop services
    log "Stopping services..."
    docker-compose -f docker-compose.production.yml down
    
    # Restore Vault
    if [[ -f "$backup_path/vault-snapshot.snap" ]]; then
        log "Restoring Vault snapshot..."
        # This requires manual intervention in production
        log "Vault snapshot available at: $backup_path/vault-snapshot.snap"
        log "To restore: vault operator raft snapshot restore $backup_path/vault-snapshot.snap"
    fi
    
    # Restore Nomad data
    if [[ -f "$backup_path/nomad_data.tar.gz" ]]; then
        log "Restoring Nomad data..."
        docker volume rm nomad_data 2>/dev/null || true
        docker volume create nomad_data
        docker run --rm \
            -v nomad_data:/data \
            -v "$backup_path:/backup" \
            alpine tar xzf /backup/nomad_data.tar.gz -C /data
    fi
    
    # Restore Consul
    if [[ -f "$backup_path/consul-snapshot.snap" ]]; then
        log "Restoring Consul snapshot..."
        docker volume rm consul_data 2>/dev/null || true
        docker volume create consul_data
        # Start consul temporarily for restore
        docker run -d --name consul-restore \
            -v consul_data:/consul/data \
            -v "$backup_path:/backup" \
            consul:latest agent -dev
        sleep 5
        docker exec consul-restore consul snapshot restore /backup/consul-snapshot.snap
        docker stop consul-restore
        docker rm consul-restore
    fi
    
    # Restore KV data
    if [[ -f "$backup_path/consul-kv.json" ]]; then
        log "Consul KV data available for restore at: $backup_path/consul-kv.json"
    fi
    
    # Restore configurations
    log "Restoring configurations..."
    cp -r "$backup_path/vault.d" /etc/ 2>/dev/null || true
    cp -r "$backup_path/nomad.d" /etc/ 2>/dev/null || true
    cp -r "$backup_path/consul.d" /etc/ 2>/dev/null || true
    
    # Restore certificates
    cp -r "$backup_path/ssl_private"/* /etc/ssl/private/ 2>/dev/null || true
    cp -r "$backup_path/ssl_certs"/* /etc/ssl/certs/ 2>/dev/null || true
    
    # Start services
    log "Starting services..."
    docker-compose -f docker-compose.production.yml up -d
    
    # Cleanup
    rm -rf "$restore_dir"
    
    log "Restore completed"
}

list_backups() {
    log "Available backups:"
    find "$BACKUP_DIR" -name "infrastructure_backup_*" -type f | sort -r | while read -r backup; do
        local size=$(du -h "$backup" | cut -f1)
        local date=$(stat -c %y "$backup" | cut -d' ' -f1)
        echo "  $(basename "$backup") - $size - $date"
    done
}

cleanup_old_backups() {
    log "Cleaning up backups older than $RETENTION_DAYS days..."
    find "$BACKUP_DIR" -name "infrastructure_backup_*" -type f -mtime +$RETENTION_DAYS -delete
    log "Cleanup completed"
}

schedule_backup() {
    local cron_schedule="$1"
    local cron_job="$cron_schedule $0 backup"
    
    # Add to crontab
    (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
    log "Backup scheduled: $cron_schedule"
}

case "${1:-help}" in
    backup)
        create_backup
        cleanup_old_backups
        ;;
    restore)
        if [[ $# -lt 2 ]]; then
            echo "Usage: $0 restore <backup-file>"
            exit 1
        fi
        restore_backup "$2"
        ;;
    list)
        list_backups
        ;;
    cleanup)
        cleanup_old_backups
        ;;
    schedule)
        if [[ $# -lt 2 ]]; then
            echo "Usage: $0 schedule '<cron-schedule>'"
            echo "Example: $0 schedule '0 2 * * *'  # Daily at 2 AM"
            exit 1
        fi
        schedule_backup "$2"
        ;;
    *)
        echo "Usage: $0 {backup|restore|list|cleanup|schedule}"
        echo ""
        echo "Commands:"
        echo "  backup                   Create a new backup"
        echo "  restore <backup-file>    Restore from backup"
        echo "  list                     List available backups"
        echo "  cleanup                  Remove old backups"
        echo "  schedule '<cron>'        Schedule automated backups"
        exit 1
        ;;
esac
```

This comprehensive infrastructure documentation provides:

1. **Architecture Overview** with detailed component descriptions
2. **Component Guides** for Vault, Nomad, Consul, and Traefik
3. **Integration Examples** with real code samples
4. **Security Best Practices** with hardening guides
5. **Monitoring Setup** with Prometheus, Grafana, and alerting
6. **Scaling Strategies** for both horizontal and vertical scaling
7. **CI/CD Integration** for GitHub Actions, Jenkins, and GitLab
8. **Troubleshooting Guide** with common issues and solutions
9. **Automation Scripts** for deployment, backup, and management

The documentation is structured to be both comprehensive and practical, providing everything needed to understand, deploy, and maintain the HashiCorp infrastructure stack with Traefik.