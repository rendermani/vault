# Traefik Nomad Pack - Phase 6 Production Deployment

This Nomad Pack provides a production-ready deployment of Traefik reverse proxy with enterprise security features, Vault integration, and automated SSL certificate management.

## Features

### 🔒 Security & SSL
- **Let's Encrypt ACME** - Automatic SSL certificate generation and renewal
- **Vault Agent Sidecar** - Secure secret management and templating
- **TLS 1.2+ Enforcement** - Modern cipher suites and security headers
- **Rate Limiting** - Built-in DDoS protection and abuse prevention
- **Dashboard Authentication** - Vault-managed credentials

### 🚀 High Availability
- **Multi-instance Deployment** - 3-node cluster with load balancing
- **Health Checks** - HTTP and TCP health monitoring
- **Graceful Updates** - Zero-downtime deployment strategy
- **Auto-recovery** - Automatic restart on failures

### 🔍 Service Discovery
- **Consul Integration** - Service mesh and service discovery
- **Nomad Provider** - Native Nomad workload discovery
- **Dynamic Configuration** - Hot-reload of routing rules

### 📊 Observability
- **Prometheus Metrics** - Comprehensive performance monitoring
- **Access Logs** - JSON-formatted request logging
- **Distributed Tracing** - Jaeger integration (optional)
- **Health Endpoints** - Built-in health check endpoints

## Quick Start

### Prerequisites

1. **Nomad Pack CLI** installed
2. **Vault** cluster running and accessible
3. **Consul** cluster for service discovery
4. **Host volumes** configured on Nomad clients

### Basic Deployment

```bash
# Deploy with default production settings
./deploy.sh

# Deploy to staging environment
ENVIRONMENT=staging ./deploy.sh

# Dry run to validate configuration
DRY_RUN=true ./deploy.sh
```

### Manual Deployment

```bash
# Render and validate
nomad-pack render . --name traefik > traefik.nomad
nomad job validate traefik.nomad

# Deploy
nomad-pack run . --name traefik
```

## Configuration

### Required Vault Secrets

Before deployment, ensure these secrets exist in Vault:

```bash
# Cloudflare DNS challenge credentials
vault kv put kv/cloudflare \
  api_key="your_cloudflare_api_key" \
  email="your_cloudflare_email"

# Dashboard authentication (bcrypt hash)
vault kv put kv/traefik/dashboard \
  basic_auth='admin:$2y$10$...'
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ENVIRONMENT` | Deployment environment | `production` |
| `DRY_RUN` | Validation only | `false` |

### Pack Variables

#### Core Configuration
- `traefik_version` - Docker image version (default: `v3.1`)
- `count` - Number of instances (default: `3`)
- `environment` - Deployment environment (default: `production`)

#### Vault Integration
- `vault_integration` - Enable Vault secrets (default: `true`)
- `vault_agent_enabled` - Enable Vault Agent sidecar (default: `true`)
- `vault_policies` - Vault policies (default: `["traefik-policy"]`)
- `vault_address` - Vault server URL

#### SSL/ACME Configuration
- `acme_enabled` - Enable Let's Encrypt (default: `true`)
- `acme_email` - ACME registration email
- `acme_ca_server` - ACME server URL
- `domains` - SSL certificate domains

#### Service Discovery
- `consul_integration` - Enable Consul provider (default: `true`)
- `nomad_provider_enabled` - Enable Nomad provider (default: `true`)

#### Security
- `tls_options` - TLS security settings
- `middlewares` - Security middleware list
- `dashboard_auth` - Enable dashboard authentication

## Architecture

### Components

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Vault Agent   │───▶│     Traefik      │───▶│   Services      │
│   (Sidecar)     │    │  (Load Balancer) │    │ (Vault/Consul)  │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Secret Store   │    │   SSL Certs      │    │ Service Mesh    │
│   (Vault KV)    │    │ (Let's Encrypt)  │    │   (Consul)      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### Network Flow

1. **Client Request** → Traefik (Port 443)
2. **SSL Termination** → Let's Encrypt certificates
3. **Service Discovery** → Consul/Nomad providers
4. **Load Balancing** → Backend services
5. **Metrics Collection** → Prometheus endpoint

## Service Routes

The pack automatically configures routes for HashiCorp services:

| Service | Domain | Backend |
|---------|--------|---------|
| Traefik Dashboard | `traefik.cloudya.net` | Internal API |
| Vault API | `vault.cloudya.net` | `vault.service.consul:8200` |
| Consul UI | `consul.cloudya.net` | `consul.service.consul:8500` |
| Nomad UI | `nomad.cloudya.net` | `nomad.service.consul:4646` |

## Security Hardening

### TLS Configuration
- Minimum TLS 1.2
- Strong cipher suites only
- HSTS headers enabled
- Perfect Forward Secrecy

### Security Headers
- Content Security Policy
- X-Frame-Options: DENY
- X-Content-Type-Options: nosniff
- Referrer Policy: same-origin

### Access Control
- Rate limiting (100 requests/10s burst)
- IP whitelisting support
- Basic authentication for dashboard
- Vault-managed credentials

## Monitoring & Troubleshooting

### Health Checks

```bash
# Traefik ping endpoint
curl http://localhost:8080/ping

# Metrics endpoint
curl http://localhost:8082/metrics

# Job status
nomad job status traefik
```

### Common Issues

#### Certificate Issues
```bash
# Check ACME storage
nomad alloc exec -job traefik ls -la /acme/

# Verify Cloudflare credentials
vault kv get kv/cloudflare
```

#### Service Discovery Issues
```bash
# Check Consul connectivity
nomad alloc exec -job traefik nslookup consul.service.consul

# Verify service registration
consul catalog services
```

#### Vault Integration Issues
```bash
# Check Vault Agent logs
nomad alloc logs -job traefik vault-agent

# Verify policy
vault policy read traefik-policy
```

### Log Analysis

```bash
# Traefik access logs
nomad alloc logs -job traefik -f traefik

# Vault Agent logs
nomad alloc logs -job traefik -f vault-agent

# Follow all logs
nomad alloc logs -job traefik -f
```

## Deployment Environments

### Development
- Staging ACME server
- Debug logging enabled
- Single instance
- Insecure API allowed

### Staging
- Staging ACME server
- 2 instances
- Production-like security
- Limited rate limiting

### Production
- Production ACME server
- 3 instances
- Full security hardening
- Strict rate limiting

## Backup & Recovery

### ACME Certificates
```bash
# Backup ACME data
nomad alloc exec -job traefik tar -czf /tmp/acme-backup.tar.gz /acme/

# Restore ACME data
nomad alloc exec -job traefik tar -xzf /tmp/acme-backup.tar.gz -C /
```

### Configuration Backup
```bash
# Export current configuration
nomad job inspect traefik > traefik-backup.json

# Restore from backup
nomad job run traefik-backup.json
```

## Scaling

### Horizontal Scaling
```bash
# Scale to 5 instances
nomad job scale traefik 5

# Auto-scaling (future enhancement)
nomad-autoscaler policy apply traefik-policy.hcl
```

### Performance Tuning
- Adjust resource allocations
- Configure connection pooling
- Enable caching middleware
- Optimize health check intervals

## Security Compliance

- ✅ **HTTPS Everywhere** - All traffic encrypted
- ✅ **Strong Encryption** - TLS 1.2+ with perfect forward secrecy
- ✅ **Security Headers** - OWASP recommended headers
- ✅ **Access Control** - Authentication and authorization
- ✅ **Audit Logging** - Comprehensive access logs
- ✅ **Secret Management** - Vault integration
- ✅ **Network Security** - Rate limiting and filtering

## Support & Maintenance

### Updates
```bash
# Update to new version
nomad-pack run . --name traefik --var traefik_version=v3.2

# Rolling update strategy
nomad job plan traefik.nomad
nomad job run traefik.nomad
```

### Maintenance Mode
```bash
# Graceful shutdown
nomad job stop traefik

# Drain nodes for maintenance
nomad node drain -enable <node-id>
```

## Contributing

1. Test changes in development environment
2. Validate pack rendering and job validation
3. Update documentation
4. Follow semantic versioning

## License

This Nomad Pack is part of the Cloudya infrastructure project.