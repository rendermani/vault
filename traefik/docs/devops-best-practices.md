# DevOps Best Practices: CI/CD and HashiCorp Vault Integration

## Executive Summary

This document outlines comprehensive best practices for implementing secure, automated CI/CD pipelines with HashiCorp Vault integration, focusing on production-ready patterns that emphasize automation, security, and testing.

## Table of Contents

1. [Core Principles](#core-principles)
2. [CI/CD Pipeline Best Practices](#cicd-pipeline-best-practices)
3. [HashiCorp Vault Integration](#hashicorp-vault-integration)
4. [Infrastructure as Code](#infrastructure-as-code)
5. [Security and Compliance](#security-and-compliance)
6. [Testing Strategies](#testing-strategies)
7. [Monitoring and Observability](#monitoring-and-observability)
8. [Implementation Patterns](#implementation-patterns)

## Core Principles

### Zero-Trust Architecture
- **Never trust, always verify**: Authenticate and authorize every request
- **Principle of least privilege**: Grant minimum necessary permissions
- **Continuous validation**: Ongoing verification of security posture

### Security-First Approach
- **Shift-left security**: Integrate security from the earliest stages
- **Defense in depth**: Multiple layers of security controls
- **Automated compliance**: Policy as code and automated governance

### Immutable Infrastructure
- **Container-based deployments**: Reproducible and consistent environments
- **Infrastructure versioning**: Track and rollback infrastructure changes
- **Declarative configuration**: Define desired state, not procedural steps

## CI/CD Pipeline Best Practices

### GitHub Actions Workflows

```yaml
name: Secure CI/CD Pipeline
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  security-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run Security Scan
        uses: securecodewarrior/github-action-add-sarif@v1
        with:
          sarif-file: security-scan-results.sarif
      
  test:
    needs: security-scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run Tests
        run: |
          npm ci
          npm run test:unit
          npm run test:integration
          npm run test:e2e
      
  build:
    needs: [security-scan, test]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build and Push Image
        run: |
          docker build -t ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} .
          docker push ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
      
  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment: production
    steps:
      - name: Deploy to Production
        run: |
          # Vault authentication and secret retrieval
          # Deployment automation
```

### GitLab CI/CD Pipeline

```yaml
stages:
  - security
  - test
  - build
  - deploy

variables:
  VAULT_ADDR: $VAULT_ADDR
  VAULT_ROLE: $CI_PROJECT_PATH_SLUG

security-scan:
  stage: security
  script:
    - semgrep --config=auto --json --output=semgrep-report.json .
    - trivy fs --format sarif --output trivy-report.sarif .
  artifacts:
    reports:
      sast: semgrep-report.json
      container_scanning: trivy-report.sarif

unit-tests:
  stage: test
  script:
    - npm ci
    - npm run test:coverage
  coverage: '/All files[^|]*\|[^|]*\s+([\d\.]+)/'
  artifacts:
    reports:
      coverage_report:
        coverage_format: cobertura
        path: coverage/cobertura-coverage.xml

integration-tests:
  stage: test
  services:
    - postgres:13
    - redis:6
  script:
    - npm run test:integration
  dependencies:
    - unit-tests

build-image:
  stage: build
  script:
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
  only:
    - main
    - develop

deploy-production:
  stage: deploy
  script:
    - vault auth -method=jwt role=$VAULT_ROLE jwt=$CI_JOB_JWT
    - export DATABASE_URL=$(vault kv get -field=url secret/prod/database)
    - kubectl set image deployment/app app=$CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
  environment:
    name: production
    url: https://app.example.com
  only:
    - main
```

### Jenkins Pipeline

```groovy
pipeline {
    agent any
    
    environment {
        VAULT_ADDR = credentials('vault-address')
        VAULT_TOKEN = credentials('vault-token')
        REGISTRY = 'your-registry.com'
    }
    
    stages {
        stage('Security Scan') {
            parallel {
                stage('SAST') {
                    steps {
                        script {
                            sh 'sonar-scanner -Dsonar.projectKey=myapp'
                        }
                    }
                }
                stage('Dependency Check') {
                    steps {
                        dependencyCheck additionalArguments: '--format XML --format JSON'
                    }
                }
            }
        }
        
        stage('Test') {
            parallel {
                stage('Unit Tests') {
                    steps {
                        sh 'npm run test:unit'
                    }
                    post {
                        always {
                            publishTestResults testResultsPattern: 'test-results.xml'
                        }
                    }
                }
                stage('Integration Tests') {
                    steps {
                        sh 'docker-compose -f test-compose.yml up -d'
                        sh 'npm run test:integration'
                    }
                    post {
                        always {
                            sh 'docker-compose -f test-compose.yml down'
                        }
                    }
                }
            }
        }
        
        stage('Build') {
            steps {
                script {
                    def image = docker.build("${REGISTRY}/myapp:${BUILD_NUMBER}")
                    image.push()
                    image.push('latest')
                }
            }
        }
        
        stage('Deploy') {
            when {
                branch 'main'
            }
            steps {
                script {
                    withVault(configuration: [vaultUrl: env.VAULT_ADDR, vaultCredentialId: 'vault-token']) {
                        def secrets = [
                            [path: 'secret/prod/database', engineVersion: 2, secretValues: [
                                [envVar: 'DB_PASSWORD', vaultKey: 'password']
                            ]]
                        ]
                        wrap([$class: 'VaultBuildWrapper', vaultSecrets: secrets]) {
                            sh 'kubectl set env deployment/myapp DB_PASSWORD=$DB_PASSWORD'
                            sh 'kubectl rollout restart deployment/myapp'
                        }
                    }
                }
            }
        }
    }
    
    post {
        always {
            cleanWs()
        }
        failure {
            slackSend(channel: '#alerts', message: "Pipeline failed: ${env.JOB_NAME} - ${env.BUILD_NUMBER}")
        }
    }
}
```

## HashiCorp Vault Integration

### Dynamic Secrets Management

#### Database Credentials
```bash
# Configure database secrets engine
vault secrets enable database

vault write database/config/postgres \
    plugin_name=postgresql-database-plugin \
    connection_url="postgresql://{{username}}:{{password}}@postgres:5432/myapp?sslmode=disable" \
    allowed_roles="readonly,readwrite" \
    username="vault" \
    password="vault-password"

# Create roles with TTL
vault write database/roles/readonly \
    db_name=postgres \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
                        GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h"
```

#### Cloud Provider Credentials
```bash
# AWS credentials
vault secrets enable aws
vault write aws/config/root \
    access_key=AKIA... \
    secret_key=... \
    region=us-east-1

vault write aws/roles/deploy \
    credential_type=iam_user \
    policy_document=-<<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ec2:*",
      "Resource": "*"
    }
  ]
}
EOF
```

### Policy as Code

```hcl
# Application policy
path "secret/data/myapp/prod/*" {
  capabilities = ["read"]
}

path "database/creds/readwrite" {
  capabilities = ["read"]
}

path "aws/creds/deploy" {
  capabilities = ["read"]
}

# Environment-specific policies
path "secret/data/myapp/{{identity.entity.aliases.auth_kubernetes_*.metadata.service_account_namespace}}/*" {
  capabilities = ["read"]
}
```

### CI/CD Integration Patterns

#### Kubernetes Integration
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "myapp"
        vault.hashicorp.com/agent-inject-secret-database: "database/creds/readwrite"
        vault.hashicorp.com/agent-inject-template-database: |
          {{- with secret "database/creds/readwrite" -}}
          export DATABASE_URL="postgresql://{{ .Data.username }}:{{ .Data.password }}@postgres:5432/myapp"
          {{- end -}}
    spec:
      serviceAccountName: myapp
      containers:
      - name: myapp
        image: myapp:latest
        command: ["/bin/sh"]
        args: ["-c", "source /vault/secrets/database && ./start-app"]
```

#### Docker Integration
```dockerfile
FROM hashicorp/vault:latest as vault-stage
FROM alpine:latest

# Copy vault binary
COPY --from=vault-stage /bin/vault /bin/vault

# Application setup
COPY . /app
WORKDIR /app

# Entrypoint script for secret retrieval
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
```

```bash
#!/bin/bash
# entrypoint.sh
set -e

# Authenticate with Vault
vault auth -method=aws

# Retrieve secrets
export DATABASE_PASSWORD=$(vault kv get -field=password secret/myapp/database)
export API_KEY=$(vault kv get -field=key secret/myapp/api)

# Start application
exec "$@"
```

## Infrastructure as Code

### Terraform Best Practices

#### Module Structure
```
terraform/
├── modules/
│   ├── vault/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── k8s/
│   └── monitoring/
├── environments/
│   ├── dev/
│   ├── staging/
│   └── prod/
└── shared/
    ├── terraform.tf
    └── variables.tf
```

#### Vault Provider Configuration
```hcl
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.0"
    }
  }
  
  backend "s3" {
    bucket         = "terraform-state-bucket"
    key            = "vault/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

provider "vault" {
  address = var.vault_address
  
  # Use AWS IAM for authentication
  auth_login {
    path = "auth/aws"
    
    parameters = {
      role = "terraform"
    }
  }
}

# Vault configuration
resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = "kubernetes"
}

resource "vault_kubernetes_auth_backend_config" "config" {
  backend            = vault_auth_backend.kubernetes.path
  kubernetes_host    = var.kubernetes_host
  kubernetes_ca_cert = var.kubernetes_ca_cert
}

resource "vault_kubernetes_auth_backend_role" "app" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "myapp"
  bound_service_account_names      = ["myapp"]
  bound_service_account_namespaces = ["production"]
  token_ttl                        = 3600
  token_policies                   = ["myapp-policy"]
}
```

### GitOps with ArgoCD
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vault-config
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/company/vault-config
    targetRevision: HEAD
    path: kubernetes/
  destination:
    server: https://kubernetes.default.svc
    namespace: vault
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

## Security and Compliance

### Security Scanning Integration

#### Container Scanning
```yaml
# GitHub Actions
- name: Run Trivy vulnerability scanner
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: 'myapp:${{ github.sha }}'
    format: 'sarif'
    output: 'trivy-results.sarif'

- name: Upload Trivy scan results to GitHub Security tab
  uses: github/codeql-action/upload-sarif@v2
  with:
    sarif_file: 'trivy-results.sarif'
```

#### Infrastructure Scanning
```bash
# Checkov for IaC scanning
checkov -f terraform/ --framework terraform --output json --output-file checkov-report.json

# tfsec for Terraform security scanning
tfsec terraform/ --format json --out tfsec-report.json

# Terrascan for policy validation
terrascan scan -i terraform -d terraform/ -o json > terrascan-report.json
```

### Compliance Automation

#### SOC2 Compliance
```hcl
# Vault audit logging
resource "vault_audit" "file" {
  type = "file"
  
  options = {
    file_path = "/vault/logs/audit.log"
  }
}

# Policy for audit log access
resource "vault_policy" "audit_reader" {
  name = "audit-reader"
  
  policy = <<EOT
path "sys/audit-hash/*" {
  capabilities = ["create", "update"]
}
EOT
}
```

#### PCI DSS Compliance
```yaml
# Network policies for segmentation
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-app-to-database
spec:
  podSelector:
    matchLabels:
      app: myapp
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: database
    ports:
    - protocol: TCP
      port: 5432
```

## Testing Strategies

### Unit Testing
```javascript
// Jest configuration for Node.js applications
module.exports = {
  collectCoverageFrom: [
    'src/**/*.{js,jsx,ts,tsx}',
    '!src/**/*.d.ts',
    '!src/index.js',
    '!src/serviceWorker.js'
  ],
  coverageThreshold: {
    global: {
      branches: 80,
      functions: 80,
      lines: 80,
      statements: 80
    }
  },
  testEnvironment: 'node',
  setupFilesAfterEnv: ['<rootDir>/src/setupTests.js']
};
```

### Integration Testing
```javascript
// Database integration tests with test containers
const { GenericContainer } = require('testcontainers');

describe('Database Integration', () => {
  let postgres;
  let connectionString;

  beforeAll(async () => {
    postgres = await new GenericContainer('postgres:13')
      .withEnvironment({
        POSTGRES_DB: 'testdb',
        POSTGRES_USER: 'testuser',
        POSTGRES_PASSWORD: 'testpass'
      })
      .withExposedPorts(5432)
      .start();

    const port = postgres.getMappedPort(5432);
    connectionString = `postgresql://testuser:testpass@localhost:${port}/testdb`;
  });

  afterAll(async () => {
    await postgres.stop();
  });

  test('should connect to database', async () => {
    const client = new Client({ connectionString });
    await client.connect();
    const result = await client.query('SELECT 1 as test');
    expect(result.rows[0].test).toBe(1);
    await client.end();
  });
});
```

### Contract Testing
```yaml
# Pact contract testing
version: '3.8'
services:
  pact-broker:
    image: pactfoundation/pact-broker
    environment:
      PACT_BROKER_DATABASE_URL: postgresql://pact:pact@postgres:5432/pact_broker
      PACT_BROKER_BASIC_AUTH_USERNAME: admin
      PACT_BROKER_BASIC_AUTH_PASSWORD: admin
    depends_on:
      - postgres
    ports:
      - "9292:9292"
```

### Performance Testing
```javascript
// K6 performance testing script
import http from 'k6/http';
import { check } from 'k6';

export let options = {
  stages: [
    { duration: '2m', target: 100 }, // Ramp up
    { duration: '5m', target: 100 }, // Stay at 100 users
    { duration: '2m', target: 200 }, // Ramp up to 200 users
    { duration: '5m', target: 200 }, // Stay at 200 users
    { duration: '2m', target: 0 },   // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'], // 95% of requests under 500ms
  },
};

export default function() {
  let response = http.get('https://api.example.com/health');
  check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
}
```

## Monitoring and Observability

### Metrics Collection
```yaml
# Prometheus configuration
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "alerts.yml"

scrape_configs:
  - job_name: 'kubernetes-pods'
    kubernetes_sd_configs:
    - role: pod
    relabel_configs:
    - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
      action: keep
      regex: true

  - job_name: 'vault'
    static_configs:
    - targets: ['vault:8200']
    metrics_path: '/v1/sys/metrics'
    params:
      format: ['prometheus']
```

### Alerting Rules
```yaml
# alerts.yml
groups:
- name: application.rules
  rules:
  - alert: HighErrorRate
    expr: (rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])) > 0.1
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: High error rate detected
      description: "Error rate is {{ $value }}% for {{ $labels.job }}"

  - alert: VaultSealedStatus
    expr: vault_core_unsealed == 0
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: Vault is sealed
      description: "Vault instance {{ $labels.instance }} is sealed"
```

### Distributed Tracing
```yaml
# Jaeger deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jaeger
spec:
  template:
    spec:
      containers:
      - name: jaeger
        image: jaegertracing/all-in-one:latest
        env:
        - name: COLLECTOR_OTLP_ENABLED
          value: "true"
        ports:
        - containerPort: 16686
        - containerPort: 14268
```

### Log Aggregation
```yaml
# Fluentd configuration for log collection
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd-config
data:
  fluent.conf: |
    <source>
      @type tail
      path /var/log/containers/*.log
      pos_file /var/log/fluentd-containers.log.pos
      tag kubernetes.*
      read_from_head true
      <parse>
        @type json
        time_format %Y-%m-%dT%H:%M:%S.%NZ
      </parse>
    </source>
    
    <filter kubernetes.**>
      @type kubernetes_metadata
    </filter>
    
    <match **>
      @type elasticsearch
      host elasticsearch
      port 9200
      logstash_format true
    </match>
```

## Implementation Patterns

### Blue-Green Deployment
```bash
#!/bin/bash
# Blue-Green deployment script

CURRENT_COLOR=$(kubectl get service myapp -o jsonpath='{.spec.selector.version}')
NEW_COLOR=$([ "$CURRENT_COLOR" = "blue" ] && echo "green" || echo "blue")

echo "Current deployment: $CURRENT_COLOR"
echo "Deploying to: $NEW_COLOR"

# Deploy new version
kubectl set image deployment/myapp-$NEW_COLOR myapp=myapp:$NEW_VERSION
kubectl rollout status deployment/myapp-$NEW_COLOR

# Health check
if curl -f http://myapp-$NEW_COLOR-service/health; then
    echo "Health check passed, switching traffic"
    kubectl patch service myapp -p '{"spec":{"selector":{"version":"'$NEW_COLOR'"}}}'
    echo "Traffic switched to $NEW_COLOR"
    
    # Scale down old version after grace period
    sleep 300
    kubectl scale deployment myapp-$CURRENT_COLOR --replicas=0
else
    echo "Health check failed, rolling back"
    kubectl scale deployment myapp-$NEW_COLOR --replicas=0
    exit 1
fi
```

### Canary Deployment with Istio
```yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: myapp
spec:
  http:
  - match:
    - headers:
        canary:
          exact: "true"
    route:
    - destination:
        host: myapp
        subset: canary
      weight: 100
  - route:
    - destination:
        host: myapp
        subset: stable
      weight: 90
    - destination:
        host: myapp
        subset: canary
      weight: 10
---
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: myapp
spec:
  host: myapp
  subsets:
  - name: stable
    labels:
      version: stable
  - name: canary
    labels:
      version: canary
```

### Secret Rotation Automation
```bash
#!/bin/bash
# Automated secret rotation script

VAULT_TOKEN=$(vault auth -method=aws -format=json | jq -r '.auth.client_token')
export VAULT_TOKEN

# Rotate database credentials
vault write database/rotate-credentials/myapp-db

# Update Kubernetes secret
NEW_PASSWORD=$(vault read database/creds/myapp-db -format=json | jq -r '.data.password')
kubectl patch secret myapp-db-secret -p='{"data":{"password":"'$(echo -n $NEW_PASSWORD | base64)'"}}'

# Trigger rolling restart
kubectl rollout restart deployment/myapp

# Verify deployment
kubectl rollout status deployment/myapp

echo "Secret rotation completed successfully"
```

## Conclusion

This comprehensive guide provides battle-tested patterns for implementing secure, automated CI/CD pipelines with HashiCorp Vault integration. The key to success is:

1. **Start Small**: Begin with basic implementations and gradually add complexity
2. **Automate Everything**: Reduce human error through comprehensive automation
3. **Security by Default**: Build security into every layer and process
4. **Monitor Continuously**: Implement comprehensive observability from day one
5. **Test Thoroughly**: Validate every change through automated testing
6. **Document Everything**: Maintain clear documentation and runbooks

By following these practices, organizations can achieve high levels of security, reliability, and operational efficiency in their DevOps processes.

---

*This document should be regularly updated as technologies and best practices evolve. Consider it a living document that grows with your organization's needs and the broader DevOps ecosystem.*