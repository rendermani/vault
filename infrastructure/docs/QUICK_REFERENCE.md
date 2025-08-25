# Infrastructure Deployment Quick Reference

## 🚀 Quick Start Commands

### Development
```bash
# Full development deployment
./scripts/deploy-develop.sh

# Dry run first (recommended)
./scripts/deploy-develop.sh --dry-run

# Force bootstrap (destroys existing data)
./scripts/deploy-develop.sh --force-bootstrap
```

### Staging
```bash
# Full staging deployment
./scripts/deploy-staging.sh

# Deploy specific components
./scripts/deploy-staging.sh --components vault,traefik

# Dry run with verbose output
./scripts/deploy-staging.sh --dry-run --verbose
```

### Production
```bash
# ALWAYS dry run first in production
./scripts/deploy-production.sh --dry-run

# Full production deployment (requires safety checks)
./scripts/deploy-production.sh

# Emergency deployment (skip safety checks)
./scripts/deploy-production.sh --skip-safety-checks
```

## 📋 GitHub Actions

### Manual Workflow Trigger
```bash
# Via GitHub CLI
gh workflow run deploy-infrastructure.yml \
  -f environment=develop \
  -f components=all \
  -f dry_run=true
```

### Workflow Dispatch Parameters
- `environment`: `develop` | `staging` | `production`
- `components`: `all` | `nomad` | `vault` | `traefik` | `nomad,vault`
- `force_bootstrap`: `true` | `false`
- `dry_run`: `true` | `false`

## 🔍 Health Checks

### Service Status
```bash
# Nomad cluster
nomad node status
nomad server members

# Vault status
vault status
curl -s http://localhost:8200/v1/sys/health | jq

# Traefik health
curl -s http://localhost:8080/ping
```

### Job Status
```bash
# List all jobs
nomad job status

# Specific job details
nomad job status vault-develop
nomad job status traefik

# Job logs
nomad alloc logs $(nomad job allocs vault-develop -json | jq -r '.[0].ID') vault
```

## 🔐 Vault Operations

### Development Access
```bash
# Set Vault address
export VAULT_ADDR=http://localhost:8200

# Login with development token
vault auth -method=userpass username=developer password=developer

# List secrets
vault kv list secret/
```

### Production/Staging Access
```bash
# Set Vault address (staging)
export VAULT_ADDR=https://localhost:8210
export VAULT_SKIP_VERIFY=true

# Production
export VAULT_ADDR=https://localhost:8220

# Login with token
vault auth -method=token token=<your-token>
```

### Common Vault Commands
```bash
# Status and health
vault status
vault operator raft list-peers

# Secrets management
vault kv put secret/myapp/config username=admin password=secret
vault kv get secret/myapp/config

# Policy management
vault policy list
vault policy read traefik-policy
```

## 🌐 Service Access

### Development Environment
- **Nomad UI**: http://localhost:4646
- **Vault UI**: http://localhost:8200/ui
- **Traefik Dashboard**: http://localhost:8080/dashboard/

### Staging Environment
- **Nomad UI**: http://localhost:4646
- **Vault UI**: https://localhost:8210/ui (accept self-signed cert)
- **Traefik Dashboard**: https://localhost:8080/dashboard/

### Production Environment
- **Nomad UI**: http://localhost:4646 (restricted)
- **Vault UI**: https://localhost:8220/ui (restricted)
- **Traefik Dashboard**: Not accessible (security)

## 🔧 Troubleshooting

### Common Issues
```bash
# Nomad not starting
sudo systemctl status nomad
journalctl -u nomad -f

# Vault sealed
vault operator unseal <key1>
vault operator unseal <key2>

# Traefik routing issues
curl -v http://localhost:8080/api/http/routers
curl -v http://localhost:8080/api/http/services
```

### Log Access
```bash
# System logs
journalctl -u consul -f
journalctl -u nomad -f

# Container logs via Nomad
nomad alloc logs <alloc-id> <task-name>
nomad alloc logs -f <alloc-id> <task-name>  # Follow logs

# Direct Docker logs
docker logs <container-id>
```

### Cleanup Commands
```bash
# Stop all jobs
nomad job stop traefik
nomad job stop vault-develop

# Purge job history
nomad job stop -purge vault-develop

# Clean volumes (DESTRUCTIVE)
sudo rm -rf /opt/nomad/volumes/*

# Reset everything (NUCLEAR OPTION)
sudo systemctl stop nomad consul
sudo rm -rf /opt/nomad/data /opt/consul/data
sudo rm -rf /opt/nomad/volumes/*
```

## 📊 Monitoring

### Resource Usage
```bash
# System resources
htop
df -h
free -h

# Nomad resources
nomad node status -verbose
nomad job inspect vault-develop
```

### Network Connectivity
```bash
# Port availability
netstat -tlnp | grep -E ":(4646|8200|8080)"
ss -tlnp | grep -E ":(4646|8200|8080)"

# Service connectivity
curl -I http://localhost:4646/v1/status/leader
curl -I http://localhost:8200/v1/sys/health
curl -I http://localhost:8080/ping
```

## 🔄 Component Dependencies

### Startup Order
1. **Consul** (service discovery)
2. **Nomad** (orchestration)
3. **Vault** (secrets, deployed on Nomad)
4. **Traefik** (gateway, deployed on Nomad with Vault secrets)

### Dependency Verification
```bash
# Consul → Nomad
consul members && nomad node status

# Nomad → Vault
nomad job status vault-develop && vault status

# Vault → Traefik
vault status && curl http://localhost:8080/ping
```

## 🚨 Emergency Procedures

### Service Recovery
```bash
# Restart Consul
consul leave
consul agent -dev -client=0.0.0.0 &

# Restart Nomad
nomad agent -config /opt/nomad/config/nomad.hcl &

# Redeploy Vault
nomad job run nomad/jobs/develop/vault.nomad

# Redeploy Traefik
nomad job run traefik/traefik.nomad
```

### Data Recovery
```bash
# Restore from backup (if available)
# 1. Stop all services
# 2. Restore volume data
# 3. Restart services in order

# Emergency Vault unsealing
vault operator unseal <recovery-key-1>
vault operator unseal <recovery-key-2>
vault operator unseal <recovery-key-3>
```

### Contact Information
- **Platform Engineering**: [team-email]
- **Security Team**: [security-email]
- **Emergency Hotline**: [emergency-number]

## 📝 Environment Variables

### Development
```bash
export NOMAD_ADDR=http://localhost:4646
export VAULT_ADDR=http://localhost:8200
export CONSUL_HTTP_ADDR=http://localhost:8500
```

### Staging
```bash
export NOMAD_ADDR=http://localhost:4646
export VAULT_ADDR=https://localhost:8210
export VAULT_SKIP_VERIFY=true
export CONSUL_HTTP_ADDR=http://localhost:8500
```

### Production
```bash
export NOMAD_ADDR=http://localhost:4646
export VAULT_ADDR=https://localhost:8220
export CONSUL_HTTP_ADDR=http://localhost:8500
```