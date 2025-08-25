# Cloud-Native Vault-Nomad Architecture Patterns & Best Practices 2024

## 📋 Executive Summary

This document outlines comprehensive cloud-native patterns for deploying HashiCorp Vault on Nomad with complete environment separation. Based on 2024 industry research and best practices, it provides strategic guidance for infrastructure architects implementing scalable, secure, and cost-optimized multi-environment deployments.

## 🏗️ 1. Infrastructure as Code (IaC) Patterns

### Multi-Environment Terraform Architecture

#### State File Isolation Strategy
```hcl
# Directory Structure
environments/
├── dev/
│   ├── main.tf
│   ├── terraform.tfvars
│   └── backend.tf
├── staging/
│   ├── main.tf
│   ├── terraform.tfvars
│   └── backend.tf
├── production/
│   ├── main.tf
│   ├── terraform.tfvars
│   └── backend.tf
└── modules/
    ├── vault/
    ├── nomad/
    └── networking/
```

#### Best Practices (2024)
- **Separate State Files**: Maintain isolated state files per environment to prevent cross-environment conflicts
- **Remote Backend Configuration**: Use cloud storage for state files with versioning and locking
- **Module-Based Architecture**: Create reusable modules for consistent deployments
- **Environment Promotion**: Implement automated promotion workflows with validation gates

#### Terraform Workspace Strategy
```hcl
# For environments with similar configurations
terraform workspace new dev
terraform workspace new staging  
terraform workspace new production

# Variable management per workspace
variable "environment" {
  description = "Environment name"
  type        = string
}

locals {
  env_config = {
    dev = {
      instance_type = "t3.medium"
      replica_count = 1
      vault_storage = "20Gi"
    }
    staging = {
      instance_type = "t3.large"
      replica_count = 2
      vault_storage = "50Gi"
    }
    production = {
      instance_type = "c5.xlarge"
      replica_count = 3
      vault_storage = "100Gi"
    }
  }
}
```

### DRY Principle Implementation
```hcl
# Base module pattern with environment-specific configurations
module "vault_cluster" {
  source = "./modules/vault"
  
  cluster_name     = "${var.environment}-vault"
  node_count       = local.env_config[var.environment].replica_count
  instance_type    = local.env_config[var.environment].instance_type
  storage_size     = local.env_config[var.environment].vault_storage
  
  # Environment-specific tags
  tags = merge(var.common_tags, {
    Environment = var.environment
    Project     = "vault-infrastructure"
  })
}
```

## 🔧 2. Container Orchestration with Nomad

### Vault on Nomad Job Specifications

#### Production-Ready Vault Job
```hcl
job "vault" {
  datacenters = ["dc1"]
  type        = "service"
  
  # Environment-specific constraints
  constraint {
    attribute = "${node.class}"
    value     = "vault-servers"
  }
  
  group "vault" {
    count = 3
    
    # Vault integration block
    vault {
      policies = ["vault-server"]
      change_mode = "restart"
    }
    
    # Resource allocation per environment
    task "vault" {
      driver = "docker"
      
      config {
        image = "hashicorp/vault:1.17.3"
        ports = ["http", "cluster"]
        
        mount {
          type   = "bind"
          source = "/opt/vault/config"
          target = "/vault/config"
        }
        
        mount {
          type   = "bind"
          source = "/opt/vault/data"
          target = "/vault/data"
        }
      }
      
      # Environment-specific resource allocation
      resources {
        cpu    = var.environment == "production" ? 2000 : 1000
        memory = var.environment == "production" ? 4096 : 2048
        
        network {
          port "http" {
            static = 8200
          }
          port "cluster" {
            static = 8201
          }
        }
      }
      
      # Health checks
      service {
        name = "vault"
        port = "http"
        
        check {
          type     = "http"
          path     = "/v1/sys/health"
          interval = "10s"
          timeout  = "3s"
        }
      }
      
      # Dynamic configuration from Vault
      template {
        data = <<EOH
{{ with secret "secret/vault/config" }}
storage "raft" {
  path    = "/vault/data"
  node_id = "{{ env "node.unique.name" }}"
  
  retry_join {
    {{ range service "vault" }}
    leader_api_addr = "https://{{ .Address }}:8200"
    {{ end }}
  }
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = false
  tls_cert_file = "/vault/tls/tls.crt"
  tls_key_file  = "/vault/tls/tls.key"
}

api_addr = "https://{{ env "NOMAD_IP_http" }}:8200"
cluster_addr = "https://{{ env "NOMAD_IP_cluster" }}:8201"
{{ end }}
EOH
        
        destination = "/vault/config/vault.hcl"
      }
    }
  }
}
```

### Auto-Scaling Configuration
```hcl
# Nomad autoscaling block (external autoscaler required)
scaling {
  min = var.environment == "production" ? 3 : 1
  max = var.environment == "production" ? 9 : 3
  
  policy {
    evaluation_interval = "10s"
    cooldown           = "1m"
    
    check "cpu_usage" {
      source = "prometheus"
      query  = "avg(cpu_usage_percent)"
      
      strategy "target-value" {
        target = 70
      }
    }
  }
}
```

### Best Practices for Nomad-Vault Integration

#### 1. Workload Identity Configuration
```hcl
# Vault block with workload identity
vault {
  cluster = "default"
  policies = ["vault-policy"]
  identity {
    aud = ["vault.io"]
    ttl = "1h"
  }
}
```

#### 2. Dynamic Secrets Pattern
```hcl
template {
  data = <<EOH
{{ with secret "database/creds/app-role" }}
DATABASE_USER="{{ .Data.username }}"
DATABASE_PASS="{{ .Data.password }}"
{{ end }}
EOH
  
  destination = "${NOMAD_SECRETS_DIR}/db_creds"
  change_mode = "restart"
}
```

## 🌐 3. Networking Architecture

### DNS Strategy for Multi-Environment

#### Hierarchical DNS Structure
```
Production:  vault.cloudya.net
Staging:     vault.staging.cloudya.net  
Development: vault.dev.cloudya.net
```

#### Service Discovery Integration
```hcl
# Consul service registration
service {
  name = "vault-${var.environment}"
  tags = ["${var.environment}", "vault", "secrets"]
  port = "http"
  
  # Environment-specific health checks
  check {
    name     = "Vault Health"
    type     = "http"
    path     = "/v1/sys/health?standbyok=true"
    interval = "10s"
    timeout  = "3s"
  }
}
```

### Service Mesh Patterns

#### Sidecar Proxy Configuration
```hcl
# Consul Connect sidecar for Vault
task "connect-proxy" {
  driver = "docker"
  lifecycle {
    hook    = "prestart"
    sidecar = true
  }
  
  config {
    image = "envoyproxy/envoy:v1.28-latest"
  }
  
  # Service mesh configuration
  template {
    data = <<EOH
{{ range service "vault" }}
{{ .Address }}:{{ .Port }}
{{ end }}
EOH
    destination = "${NOMAD_ALLOC_DIR}/upstream_endpoints"
  }
}
```

#### Network Segmentation
```yaml
# Kubernetes NetworkPolicy equivalent for Consul Connect
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceIntentions
metadata:
  name: vault-access
spec:
  destination:
    name: vault
  sources:
    - name: api-gateway
      action: allow
    - name: nomad-client
      action: allow
    - action: deny # Default deny
```

### Load Balancing Patterns

#### Layer 7 Load Balancing with Traefik
```yaml
# Traefik configuration for environment-specific routing
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: vault-ingress
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`vault.${ENVIRONMENT}.cloudya.net`)
      kind: Rule
      services:
        - name: vault
          port: 8200
          strategy: RoundRobin
          healthcheck:
            path: /v1/sys/health
            interval: 30s
```

## 💰 4. Cost Optimization Strategies

### Multi-Environment Cost Optimization

#### Instance Mix Strategy (2024 Best Practices)
```yaml
environments:
  development:
    compute:
      - type: spot_instances
        percentage: 80%
        instance_types: ["t3.medium", "t3.large"]
      - type: on_demand
        percentage: 20%
        instance_types: ["t3.medium"]
    
  staging:
    compute:
      - type: spot_instances
        percentage: 60%
        instance_types: ["t3.large", "c5.large"]
      - type: reserved_instances
        percentage: 40%
        term: "1_year"
        instance_types: ["c5.large"]
  
  production:
    compute:
      - type: reserved_instances
        percentage: 70%
        term: "3_year"
        instance_types: ["c5.xlarge", "c5.2xlarge"]
      - type: on_demand
        percentage: 30%
        instance_types: ["c5.xlarge"]
```

#### Resource Sharing Patterns
```hcl
# Shared infrastructure components
module "shared_networking" {
  source = "./modules/shared-networking"
  
  # VPC shared across non-production environments
  enable_multi_tenancy = var.environment != "production"
  
  subnets = {
    dev = {
      cidr = "10.0.1.0/24"
      availability_zones = ["us-west-2a"]
    }
    staging = {
      cidr = "10.0.2.0/24"
      availability_zones = ["us-west-2b"]
    }
  }
}

# Production isolation
module "production_networking" {
  source = "./modules/dedicated-networking"
  count  = var.environment == "production" ? 1 : 0
  
  vpc_cidr = "10.1.0.0/16"
  availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]
}
```

#### Automated Cost Monitoring
```hcl
# CloudWatch alarms for cost monitoring
resource "aws_cloudwatch_metric_alarm" "cost_alarm" {
  alarm_name          = "${var.environment}-cost-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = "86400"
  statistic           = "Maximum"
  threshold           = var.cost_thresholds[var.environment]
  alarm_description   = "This metric monitors ${var.environment} environment costs"
  alarm_actions       = [aws_sns_topic.cost_alerts.arn]

  dimensions = {
    Currency = "USD"
    LinkedAccount = data.aws_caller_identity.current.account_id
  }
}
```

## 🚀 5. GitOps Deployment Patterns

### ArgoCD Multi-Environment Configuration

#### Repository Structure
```
vault-gitops/
├── environments/
│   ├── dev/
│   │   ├── kustomization.yaml
│   │   └── values.yaml
│   ├── staging/
│   │   ├── kustomization.yaml
│   │   └── values.yaml
│   └── production/
│       ├── kustomization.yaml
│       └── values.yaml
├── base/
│   ├── vault-deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
└── charts/
    └── vault/
```

#### ArgoCD Application Configuration
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vault-dev
  namespace: argocd
spec:
  project: vault-project
  source:
    repoURL: https://github.com/cloudya/vault-gitops
    targetRevision: HEAD
    path: environments/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: vault-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

### Environment Promotion Pipeline
```yaml
# GitHub Actions workflow for environment promotion
name: Environment Promotion
on:
  push:
    branches: [main]

jobs:
  deploy-dev:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Deploy to Development
        run: |
          argocd app sync vault-dev
          argocd app wait vault-dev --health
  
  promote-staging:
    needs: deploy-dev
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - name: Update Staging
        run: |
          # Update staging configuration
          git checkout -b staging-promotion-$(date +%s)
          # Update image tags and configurations
          git commit -m "Promote to staging"
          git push origin staging-promotion-*
  
  promote-production:
    needs: promote-staging
    runs-on: ubuntu-latest
    environment: production
    steps:
      - name: Create Production PR
        run: |
          gh pr create --title "Production Deployment" \
            --body "Automated production promotion" \
            --base production --head staging-promotion-*
```

### FluxCD Alternative Configuration
```yaml
# Flux HelmRelease for environment-specific values
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: vault
  namespace: vault-system
spec:
  interval: 10m
  chart:
    spec:
      chart: vault
      version: '0.25.0'
      sourceRef:
        kind: HelmRepository
        name: hashicorp
  values:
    global:
      enabled: true
      tlsDisable: false
    
    server:
      replicas: ${VAULT_REPLICAS}
      resources:
        requests:
          memory: "${VAULT_MEMORY}"
          cpu: "${VAULT_CPU}"
    
    injector:
      enabled: true
      replicas: 2
  
  postRenderers:
    - kustomize:
        patches:
          - target:
              kind: Deployment
              name: vault
            patch: |
              - op: add
                path: /metadata/labels/environment
                value: ${ENVIRONMENT}
```

## 🔐 6. Security Patterns & Best Practices

### Multi-Tenant Security Isolation

#### Vault Policy Segmentation
```hcl
# Environment-specific policies
path "secret/data/${ENVIRONMENT}/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/data/shared/*" {
  capabilities = ["read", "list"]
}

# Cross-environment restrictions
path "secret/data/production/*" {
  capabilities = ["deny"]
}
```

#### Nomad ACL Configuration
```hcl
# Environment-specific ACL policies
acl_policy "vault-${var.environment}" {
  description = "Vault policy for ${var.environment}"
  
  job {
    policy = "write"
    
    # Environment-specific job constraints
    constraint {
      attribute = "${meta.environment}"
      value     = var.environment
    }
  }
  
  node {
    policy = "read"
  }
  
  namespace "${var.environment}" {
    policy = "write"
    
    capabilities = ["submit-job", "dispatch-job", "read-logs"]
  }
}
```

### Container Security Hardening

#### Pod Security Standards
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: vault-pod
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "vault-role"
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 2000
    seccompProfile:
      type: RuntimeDefault
  
  containers:
  - name: vault
    image: hashicorp/vault:1.17.3
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
        add:
        - IPC_LOCK # Required for Vault
```

#### Network Security Policies
```yaml
# Kubernetes NetworkPolicy for Vault isolation
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: vault-network-policy
spec:
  podSelector:
    matchLabels:
      app: vault
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: nomad-system
    ports:
    - protocol: TCP
      port: 8200
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: consul-system
    ports:
    - protocol: TCP
      port: 8500
```

## 📊 7. Monitoring & Observability

### Multi-Environment Monitoring Stack

#### Prometheus Configuration
```yaml
# Prometheus scrape configuration
scrape_configs:
  - job_name: 'vault-dev'
    consul_sd_configs:
      - server: 'consul.dev.cloudya.net:8500'
        services: ['vault']
    relabel_configs:
      - source_labels: [__meta_consul_service_metadata_environment]
        target_label: environment
      - source_labels: [__meta_consul_service]
        target_label: service

  - job_name: 'vault-production'
    consul_sd_configs:
      - server: 'consul.cloudya.net:8500'
        services: ['vault']
    relabel_configs:
      - source_labels: [__meta_consul_service_metadata_environment]
        target_label: environment
        replacement: 'production'
```

#### Grafana Dashboard Configuration
```json
{
  "dashboard": {
    "title": "Vault Multi-Environment Dashboard",
    "panels": [
      {
        "title": "Vault Health by Environment",
        "type": "stat",
        "targets": [
          {
            "expr": "up{job=~\"vault-.*\"}",
            "legendFormat": "{{environment}}"
          }
        ]
      },
      {
        "title": "Token Operations Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(vault_token_create_count[5m])",
            "legendFormat": "{{environment}} - Creates"
          }
        ]
      }
    ]
  }
}
```

### Alerting Configuration
```yaml
# AlertManager rules
groups:
- name: vault.rules
  rules:
  - alert: VaultDown
    expr: up{job=~"vault-.*"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Vault instance is down"
      description: "Vault instance in {{ $labels.environment }} has been down for more than 1 minute"
  
  - alert: VaultHighTokenCreation
    expr: rate(vault_token_create_count[5m]) > 100
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High token creation rate in {{ $labels.environment }}"
```

## 🎯 8. Implementation Roadmap

### Phase 1: Foundation (Weeks 1-4)
1. **Infrastructure Setup**
   - Deploy Terraform modules for each environment
   - Configure separate state files and remote backends
   - Set up VPC and networking isolation

2. **Basic Vault Deployment**
   - Deploy Vault clusters per environment
   - Configure basic authentication and policies
   - Implement TLS and basic security hardening

### Phase 2: Orchestration (Weeks 5-8)
1. **Nomad Integration**
   - Deploy Nomad clusters
   - Configure Vault-Nomad integration
   - Implement job specifications with resource allocation

2. **Service Discovery**
   - Deploy Consul for service discovery
   - Configure DNS strategies
   - Implement health checking

### Phase 3: Advanced Features (Weeks 9-12)
1. **GitOps Implementation**
   - Set up ArgoCD/FluxCD
   - Configure environment promotion pipelines
   - Implement automated deployment workflows

2. **Security Hardening**
   - Implement advanced security policies
   - Configure multi-tenancy isolation
   - Set up comprehensive auditing

### Phase 4: Optimization (Weeks 13-16)
1. **Cost Optimization**
   - Implement spot instance strategies
   - Configure auto-scaling policies
   - Set up cost monitoring and alerts

2. **Observability**
   - Deploy monitoring stack
   - Configure alerting rules
   - Implement performance dashboards

## 📈 Success Metrics

### Key Performance Indicators (KPIs)
- **Availability**: 99.9% uptime per environment
- **Recovery Time**: < 15 minutes for planned operations
- **Cost Efficiency**: 30-50% cost reduction through optimization
- **Security**: Zero security incidents from environment isolation failures
- **Deployment Frequency**: Daily deployments to development, weekly to production

### Monitoring Dashboards
- Environment health and status
- Cost tracking per environment
- Security audit compliance
- Performance metrics and SLAs

## 🔄 Maintenance & Operations

### Regular Operations Tasks
- **Daily**: Health checks, cost monitoring, security event review
- **Weekly**: Performance analysis, capacity planning
- **Monthly**: Security audits, policy reviews, cost optimization analysis
- **Quarterly**: Disaster recovery testing, architecture reviews

### Emergency Procedures
- Environment isolation protocols
- Cross-environment contamination prevention
- Incident response procedures
- Escalation paths and contact information

---

## 📚 Additional Resources

### Documentation References
- [HashiCorp Vault Documentation](https://developer.hashicorp.com/vault)
- [HashiCorp Nomad Documentation](https://developer.hashicorp.com/nomad)
- [Terraform Best Practices](https://developer.hashicorp.com/terraform/cloud-docs/recommended-practices)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [FluxCD Documentation](https://fluxcd.io/docs/)

### Community Resources
- CNCF Cloud Native Landscape
- HashiCorp User Groups
- Kubernetes SIG-Auth
- Cloud Native Security Working Group

---

*This document represents current best practices as of 2024 and should be regularly updated to reflect evolving technologies and security requirements.*

**Document Version**: 1.0  
**Last Updated**: $(date +"%Y-%m-%d")  
**Review Cycle**: Quarterly  
**Next Review**: $(date -d "+3 months" +"%Y-%m-%d")