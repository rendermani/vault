# Vault-Traefik Integration Guide

Complete guide for deploying and managing the automated Vault-Traefik integration.

## Overview

This integration provides:
- **Zero-manual-steps deployment**: Complete automation from initialization to production
- **Secure credential management**: All secrets stored in Vault, no hardcoded credentials
- **Automatic certificate provisioning**: Let's Encrypt certificates via Traefik
- **Health monitoring**: Continuous monitoring and automatic recovery
- **Credential rotation**: Automated weekly credential rotation
- **High availability**: Vault Agent ensures secret availability

## Architecture

```
┌────────────────┐    ┌────────────────┐
│      Vault      │    │   Vault Agent   │
│   (Secrets)    │────│  (Templates)   │
│                │    │                │
└────────────────┘    └────────────────┘
           │                     │
           │                     │
           │                     │
    ┌───────────────────────────────┐
    │           Traefik            │
    │   (Load Balancer + SSL)     │
    │                             │
    └───────────────────────────────┘
           │
    ┌───────────────────────────────┐
    │      Backend Services       │
    │   (Vault, Nomad, Apps)     │
    └───────────────────────────────┘
```

## Quick Start

### Prerequisites

- Vault server running and accessible
- Nomad cluster running
- Root or sudo access
- Required tools: `vault`, `nomad`, `curl`, `jq`, `htpasswd`

### One-Command Deployment

```bash
# Complete automated deployment
sudo /path/to/infrastructure/scripts/deploy-vault-traefik-integration.sh
```

This single command will:
1. Initialize Vault (if needed)
2. Create all necessary secrets
3. Configure Vault Agent
4. Deploy Traefik with Vault integration
5. Set up health monitoring
6. Configure automatic credential rotation
7. Run comprehensive tests

## Manual Step-by-Step (if needed)

### Step 1: Initialize Vault Integration

```bash
# Run Vault initialization script
sudo /path/to/infrastructure/scripts/automated-vault-traefik-init.sh
```

This will:
- Initialize Vault (if not already done)
- Enable KV secrets engine
- Create Traefik policy
- Generate and store dashboard credentials
- Create service token
- Configure certificate storage

### Step 2: Deploy Traefik Job

```bash
# Deploy Traefik with Vault integration
nomad job run /path/to/infrastructure/traefik/traefik-vault-integration.nomad
```

### Step 3: Verify Integration

```bash
# Run comprehensive test suite
sudo /path/to/infrastructure/scripts/test-vault-traefik-integration.sh
```

## Configuration Files

### Key Files

| File | Purpose |
|------|----------|
| `automated-vault-traefik-init.sh` | Complete Vault initialization |
| `deploy-vault-traefik-integration.sh` | Full deployment automation |
| `test-vault-traefik-integration.sh` | Comprehensive test suite |
| `traefik-vault-integration.nomad` | Nomad job with Vault Agent sidecar |
| `vault-agent.hcl` | Vault Agent configuration |
| `templates/*.tpl` | Vault template files |

### Vault Secret Paths

| Path | Contents | Purpose |
|------|----------|----------|
| `secret/traefik/dashboard` | `username`, `password`, `auth` | Dashboard authentication |
| `secret/traefik/vault` | `token` | Service token for Vault access |
| `secret/traefik/certificates` | `acme_email`, `domain` | Certificate configuration |
| `secret/traefik/cloudflare` | `email`, `api_key` | DNS challenge (optional) |

## Service Endpoints

After deployment, these services will be available:

- **Traefik Dashboard**: https://traefik.cloudya.net
- **Vault UI**: https://vault.cloudya.net
- **Nomad UI**: https://nomad.cloudya.net
- **Metrics**: https://metrics.cloudya.net
- **Grafana**: https://grafana.cloudya.net

## Security Features

### Authentication
- Dashboard protected with bcrypt-hashed credentials
- All credentials stored securely in Vault
- Service-specific tokens with limited permissions
- Automatic token renewal

### TLS/SSL
- Automatic Let's Encrypt certificate provisioning
- HTTPS-only with HTTP redirect
- Strong cipher suites and TLS 1.2+ only
- HSTS headers and security headers

### Network Security
- Host network mode for optimal performance
- Isolated secret storage
- Vault Agent local caching
- Health check endpoints

## Monitoring and Maintenance

### Health Checks

- **Automated health monitoring** every 5 minutes
- **Service connectivity tests** for all endpoints
- **Vault integration validation**
- **Certificate expiry monitoring**

### Credential Rotation

- **Automatic rotation** every Sunday at 2:00 AM
- **Zero-downtime** credential updates
- **Rollback capability** in case of issues
- **Audit logging** of all rotations

### Logs

| Service | Log Location |
|---------|-------------|
| Deployment | `/var/log/vault-traefik-deployment.log` |
| Vault Agent | `/var/log/vault-agent-traefik.log` |
| Health Checks | `/var/log/vault-traefik-health.log` |
| Credential Rotation | `/var/log/traefik-credential-rotation.log` |
| Tests | `/var/log/vault-traefik-integration-test.log` |

## Troubleshooting

### Common Issues

#### 1. Vault Not Accessible
```bash
# Check Vault status
vault status

# Check Vault service
systemctl status vault

# Check logs
journalctl -u vault -f
```

#### 2. Traefik Job Not Starting
```bash
# Check job status
nomad job status traefik-vault

# Check allocation logs
nomad alloc logs <allocation-id>

# Check host volumes
ls -la /opt/nomad/volumes/
```

#### 3. Certificates Not Working
```bash
# Check ACME storage
sudo cat /opt/nomad/volumes/traefik-certs/acme.json

# Check Traefik logs
nomad alloc logs <allocation-id> traefik

# Test HTTP challenge
curl -v http://traefik.cloudya.net/.well-known/acme-challenge/test
```

#### 4. Dashboard Authentication Issues
```bash
# Check credentials in Vault
vault kv get secret/traefik/dashboard

# Check rendered auth file
sudo cat /opt/nomad/volumes/traefik-config/dashboard-auth

# Check Vault Agent status
systemctl status vault-agent
```

### Debug Commands

```bash
# Run health check manually
sudo /usr/local/bin/vault-traefik-health-check

# Check Vault Agent cache
curl http://localhost:8100/agent/v1/cache-status

# Test credential rotation
sudo /usr/local/bin/rotate-traefik-credentials

# Run comprehensive tests
sudo /path/to/scripts/test-vault-traefik-integration.sh
```

## Backup and Recovery

### Backup Important Data

```bash
# Backup Vault data
vault operator raft snapshot save vault-backup-$(date +%Y%m%d).snap

# Backup certificates
tar czf traefik-certs-backup-$(date +%Y%m%d).tar.gz /opt/nomad/volumes/traefik-certs/

# Backup configuration
tar czf traefik-config-backup-$(date +%Y%m%d).tar.gz /opt/nomad/volumes/traefik-config/
```

### Recovery Procedures

```bash
# Restore Vault snapshot
vault operator raft snapshot restore vault-backup-YYYYMMDD.snap

# Redeploy Traefik job
nomad job run /path/to/traefik-vault-integration.nomad

# Restart services
sudo systemctl restart vault-agent
```

## Performance Tuning

### Resource Allocation

- **Vault Agent**: 100 CPU, 128MB RAM
- **Traefik**: 500 CPU, 512MB RAM
- **Storage**: Host volumes for persistence

### Optimization Settings

- **Vault Agent caching** enabled for faster secret retrieval
- **Template refresh intervals** optimized for balance
- **Health check intervals** tuned for responsiveness
- **Connection pooling** for backend services

## Advanced Configuration

### Custom Domain Configuration

Edit the dynamic configuration template to add new domains:

```yaml
# In dynamic-config.tpl
routers:
  custom-app:
    rule: "Host(`custom.cloudya.net`)"
    service: custom-service
    middlewares:
      - security-headers
    tls:
      certResolver: letsencrypt
```

### Additional Middleware

Add custom middleware in the dynamic configuration:

```yaml
middlewares:
  custom-auth:
    basicAuth:
      users:
{{- with secret "secret/custom/auth" }}
        - "{{ .Data.data.auth }}"
{{- end }}
```

### DNS Challenge (Cloudflare)

To enable DNS challenge for wildcard certificates:

1. Store Cloudflare credentials in Vault:
   ```bash
   vault kv put secret/traefik/cloudflare \
     email="your-email@cloudflare.com" \
     api_key="your-api-key"
   ```

2. Uncomment DNS challenge section in Traefik configuration

## API Reference

### Health Check Endpoints

- **Traefik Health**: `http://localhost/ping`
- **Vault Agent**: `http://localhost:8100/agent/v1/cache-status`
- **Metrics**: `http://localhost:8082/metrics`

### Management Commands

```bash
# Deploy integration
sudo ./deploy-vault-traefik-integration.sh

# Test integration
sudo ./test-vault-traefik-integration.sh

# Initialize Vault only
sudo ./automated-vault-traefik-init.sh

# Manual health check
sudo /usr/local/bin/vault-traefik-health-check

# Manual credential rotation
sudo /usr/local/bin/rotate-traefik-credentials
```

## Support and Maintenance

### Regular Maintenance Tasks

- **Weekly**: Review credential rotation logs
- **Monthly**: Update Traefik and Vault versions
- **Quarterly**: Certificate renewal verification
- **Annually**: Security policy review

### Monitoring Checklist

- [ ] All services responding to health checks
- [ ] Certificates auto-renewing properly
- [ ] Credential rotation working
- [ ] No failed authentication attempts
- [ ] Vault unsealed and accessible
- [ ] Nomad cluster healthy

---

**Note**: This integration is designed for production use with comprehensive security, monitoring, and automation features. All credentials are managed securely through Vault with no manual intervention required after initial deployment.