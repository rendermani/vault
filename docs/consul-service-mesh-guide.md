# Consul Service Mesh (Connect) Configuration Guide

## Overview

This guide covers the secure configuration and management of Consul Connect service mesh features, including mTLS, service intentions, and sidecar proxy deployment.

## Current Service Mesh Assessment

### Existing Configuration
```hcl
connect {
  enabled = true
}
```

### Security Gaps Identified
1. **Default CA Configuration** - Using built-in CA instead of Vault integration
2. **No Service Intentions** - All services can communicate with each other
3. **Missing Proxy Configuration** - No sidecar deployment strategy
4. **No mTLS Enforcement** - Service-to-service encryption optional

## Production-Ready Service Mesh Configuration

### 1. Vault Integration for CA Management

```hcl
# Production Connect configuration with Vault CA
connect {
  enabled = true
  ca_provider = "vault"
  ca_config {
    address = "https://vault.service.consul:8200"
    token = "{{ env \"CONSUL_VAULT_TOKEN\" }}"
    root_pki_path = "connect_root"
    intermediate_pki_path = "connect_inter"
    leaf_cert_ttl = "72h"
    intermediate_cert_ttl = "8760h"  # 1 year
    root_cert_ttl = "87600h"         # 10 years
    rotation_period = "2160h"        # 90 days
  }
}
```

### 2. Service Intentions (Zero-Trust Networking)

#### Default Deny Policy
```bash
# Set default intention to deny all communications
consul intention create -deny "*" "*"
```

#### Explicit Service Communications
```bash
# Allow frontend to communicate with backend
consul intention create -allow frontend backend

# Allow backend to communicate with database
consul intention create -allow backend database

# Allow monitoring to scrape all services
consul intention create -allow monitoring "*"

# Allow Vault to communicate with Consul
consul intention create -allow vault consul
```

### 3. Service Registration with Sidecar Proxies

#### Frontend Service with Sidecar
```json
{
  "ID": "frontend-v1",
  "Name": "frontend",
  "Tags": ["v1", "web"],
  "Port": 3000,
  "Connect": {
    "SidecarService": {
      "Port": 21000,
      "Check": {
        "Name": "Connect Envoy Sidecar",
        "TCP": "127.0.0.1:21000",
        "Interval": "10s"
      },
      "Proxy": {
        "Upstreams": [
          {
            "DestinationName": "backend",
            "LocalBindPort": 8080
          }
        ]
      }
    }
  },
  "Check": {
    "HTTP": "http://127.0.0.1:3000/health",
    "Interval": "30s"
  }
}
```

#### Backend Service with Database Connection
```json
{
  "ID": "backend-v1",
  "Name": "backend",
  "Tags": ["v1", "api"],
  "Port": 8000,
  "Connect": {
    "SidecarService": {
      "Port": 21001,
      "Check": {
        "Name": "Connect Envoy Sidecar",
        "TCP": "127.0.0.1:21001",
        "Interval": "10s"
      },
      "Proxy": {
        "Upstreams": [
          {
            "DestinationName": "database",
            "LocalBindPort": 5432
          },
          {
            "DestinationName": "vault",
            "LocalBindPort": 8200
          }
        ]
      }
    }
  },
  "Check": {
    "HTTP": "http://127.0.0.1:8000/health",
    "Interval": "30s"
  }
}
```

## Service Mesh Security Policies

### 1. Certificate Management

#### Automatic Certificate Rotation
```hcl
# Enable automatic certificate rotation
connect {
  ca_config {
    leaf_cert_ttl = "24h"           # Short-lived certificates
    intermediate_cert_ttl = "8760h"  # Intermediate valid for 1 year
    rotation_period = "720h"         # Rotate every 30 days
  }
}
```

#### Certificate Monitoring
```bash
#!/bin/bash
# Monitor certificate expiration
consul connect ca get-config | jq '.CreateIndex'
consul connect ca roots | jq '.Roots[].NotAfter'
```

### 2. Service Identity Validation

#### Service Identity Configuration
```hcl
# Require service identity for Connect services
connect {
  verify_incoming = true
  verify_outgoing = true
  verify_server_hostname = true
}
```

#### SPIFFE Identity Format
- Services get SPIFFE IDs: `spiffe://consul.io/ns/default/dc/dc1/svc/frontend`
- Workload identity validation through mTLS certificates

### 3. Observability and Monitoring

#### Metrics Collection
```json
{
  "telemetry": {
    "prometheus_retention_time": "60s",
    "disable_hostname": true,
    "enable_host_metrics": true
  },
  "connect": {
    "enable_serverless_plugin": true
  }
}
```

#### Distributed Tracing
```hcl
# Enable tracing for Connect services
connect {
  enable_serverless_plugin = true
  ca_config {
    cluster_id = "consul-cluster-prod"
  }
}
```

## Advanced Service Mesh Features

### 1. Traffic Management

#### Service Mesh Configuration Entry
```hcl
Kind = "service-defaults"
Name = "backend"
Protocol = "http"
MeshGateway {
  Mode = "local"
}
```

#### Load Balancing Configuration
```hcl
Kind = "service-resolver"
Name = "backend"
DefaultSubset = "v1"
Subsets = {
  "v1" = {
    Filter = "Service.Tags contains v1"
  }
  "v2" = {
    Filter = "Service.Tags contains v2"
  }
}
LoadBalancer = {
  Policy = "least_request"
  HashPolicies = [
    {
      Field = "header"
      FieldValue = "x-session-id"
    }
  ]
}
```

### 2. Service Mesh Gateways

#### Mesh Gateway Configuration
```json
{
  "ID": "mesh-gateway",
  "Name": "mesh-gateway",
  "Port": 8443,
  "Connect": {
    "Gateway": {
      "Mesh": {}
    }
  },
  "Check": {
    "Name": "Mesh Gateway Listening",
    "TCP": "127.0.0.1:8443",
    "Interval": "10s"
  }
}
```

#### Ingress Gateway for External Traffic
```json
{
  "ID": "ingress-gateway",
  "Name": "ingress-gateway", 
  "Port": 8080,
  "Connect": {
    "Gateway": {
      "Ingress": {
        "Listeners": [
          {
            "Port": 8080,
            "Protocol": "http",
            "Services": [
              {
                "Name": "frontend",
                "Hosts": ["app.example.com"]
              }
            ]
          }
        ]
      }
    }
  }
}
```

### 3. Multi-Datacenter Service Mesh

#### WAN Federation Configuration
```hcl
# Primary datacenter
datacenter = "dc1"
primary_datacenter = "dc1"

# Enable mesh gateway for WAN
connect {
  enable_mesh_gateway_wan_federation = true
  mesh_gateway_wan_federation_bind_addr = "0.0.0.0:8443"
}
```

## Service Mesh Deployment Strategies

### 1. Gradual Rollout

#### Phase 1: Enable Connect (Current Status)
- ✅ Consul Connect enabled
- ⏳ Services registered with sidecar configuration
- ⏳ Basic intentions configured

#### Phase 2: Security Hardening
- Integrate with Vault CA
- Implement zero-trust intentions
- Enable certificate rotation

#### Phase 3: Advanced Features
- Deploy service mesh gateways
- Implement traffic management
- Add observability stack

### 2. Development vs Production

#### Development Environment
```hcl
connect {
  enabled = true
  ca_provider = "consul"  # Built-in CA for development
}
```

#### Production Environment
```hcl
connect {
  enabled = true
  ca_provider = "vault"   # Vault CA for production
  ca_config {
    address = "https://vault.service.consul:8200"
    # ... additional security configuration
  }
}
```

## Service Mesh Testing and Validation

### 1. Connection Testing
```bash
# Test service-to-service communication
consul connect proxy -service frontend -upstream backend:8080 &
curl http://127.0.0.1:8080/api/health

# Validate mTLS certificates
consul connect ca roots
consul connect ca get-config
```

### 2. Intention Testing
```bash
# Test allowed connection
consul intention create -allow frontend backend
consul connect proxy -service frontend -upstream backend:8080

# Test denied connection  
consul intention create -deny frontend database
# Connection should fail
```

### 3. Certificate Validation
```bash
# Verify certificate chain
openssl s_client -connect backend.service.consul:8080 -CAfile consul-ca.pem

# Check certificate expiration
consul connect ca roots | jq '.Roots[].NotAfter'
```

## Troubleshooting Service Mesh Issues

### Common Problems and Solutions

#### 1. Certificate Issues
```bash
# Regenerate certificates
consul connect ca set-config -config-file ca-config.json

# Check certificate trust chain
consul connect ca roots
```

#### 2. Service Registration Problems
```bash
# Verify service registration
consul catalog services
consul catalog service frontend

# Check service health
consul health service frontend
```

#### 3. Intention Debugging
```bash
# List all intentions
consul intention list

# Check specific intention
consul intention get frontend backend

# Test intention with dry-run
consul intention check frontend backend
```

## Monitoring and Alerting

### Key Metrics to Monitor
- Certificate expiration times
- Service mesh connectivity rates
- Intention deny rates
- Proxy error rates
- Service discovery health

### Alerting Rules
```yaml
# Example Prometheus alerts
groups:
- name: consul-connect
  rules:
  - alert: ConsulConnectCertificateExpiring
    expr: consul_connect_cert_expiry_seconds < 86400
    for: 5m
    annotations:
      summary: "Consul Connect certificate expiring soon"
      
  - alert: ConsulConnectServiceDown
    expr: consul_catalog_service_up == 0
    for: 2m
    annotations:
      summary: "Consul Connect service is down"
```

This service mesh configuration provides a foundation for secure, observable, and manageable service-to-service communication in your infrastructure.