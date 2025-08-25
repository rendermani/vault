# Remote Infrastructure Deployment Guide

This guide explains how to deploy the Vault, Nomad, and Traefik infrastructure to a remote server using GitHub Actions.

## Overview

The deployment system uses GitHub Actions to:
1. Test infrastructure locally with Docker Compose (on PRs)
2. Deploy infrastructure to remote server via SSH (on pushes to main/develop)

## Prerequisites

### Required GitHub Secrets

Configure these secrets in your GitHub repository settings:

- `SSH_PRIVATE_KEY`: Private SSH key for connecting to the remote server
- `NOMAD_BOOTSTRAP_TOKEN`: Bootstrap token for Nomad (generate with `openssl rand -hex 32`)
- `CONSUL_BOOTSTRAP_TOKEN`: Bootstrap token for Consul (generate with `openssl rand -hex 32`)

### Remote Server Requirements

The target server (root@cloudya.net) must:
- Be accessible via SSH on port 22
- Have root access available
- Have sufficient resources (2+ CPU cores, 4+ GB RAM recommended)

## Deployment Process

### Automatic Deployment

**Develop Environment:**
```bash
git push origin develop
```
- Automatically deploys to develop environment
- Uses existing deployment if available, or bootstraps if needed

**Production Environment:**
```bash
git push origin main
```
- Automatically deploys to production environment
- More conservative deployment with enhanced security

### Manual Deployment

Use GitHub Actions workflow dispatch for manual control:

1. Go to Actions tab in GitHub repository
2. Select "Deploy Infrastructure - Remote Server (root@cloudya.net)"
3. Click "Run workflow"
4. Configure options:
   - **Environment**: develop, staging, or production
   - **Components**: all, nomad, vault, traefik, or comma-separated list
   - **Force Bootstrap**: Destroys existing data and starts fresh
   - **Dry Run**: Validates configuration without deployment

## Local Testing

Before deploying to remote server, test locally:

```bash
# Test with Docker Compose
docker-compose -f docker-compose.local-test.yml up -d

# Wait for services to start
sleep 30

# Open test application
open http://localhost/

# Check individual services
open http://localhost:8500  # Consul
open http://localhost:4646  # Nomad
open http://localhost:8200  # Vault
open http://localhost:8080  # Traefik

# Test deployment script
./scripts/unified-bootstrap.sh --environment develop --dry-run --verbose

# Cleanup
docker-compose -f docker-compose.local-test.yml down -v
```

## Remote Access

After successful deployment, access services via SSH tunnel:

```bash
# Create SSH tunnel to remote server
ssh -L 4646:localhost:4646 -L 8200:localhost:8200 -L 8080:localhost:8080 root@cloudya.net

# In another terminal, access services locally:
open http://localhost:4646  # Nomad UI
open http://localhost:8200  # Vault UI  
open http://localhost:8080  # Traefik Dashboard
```

## Workflow Structure

### Jobs

1. **local-testing** (PR only)
   - Validates Docker Compose configuration
   - Runs local infrastructure stack
   - Tests service connectivity
   - Validates deployment scripts

2. **prepare-deployment** (Push/Manual)
   - Determines environment and components
   - Validates deployment strategy
   - Sets up deployment configuration

3. **setup-remote-server** (Push/Manual)
   - Establishes SSH connection
   - Installs required tools on remote server
   - Transfers infrastructure code

4. **deploy-infrastructure** (Push/Manual)
   - Executes deployment on remote server
   - Validates service health
   - Collects logs and creates artifacts
   - Generates deployment summary

## Security Features

- SSH key-based authentication
- Encrypted secrets management
- Bootstrap token rotation
- Vault-managed service tokens
- Secure cleanup of temporary files

## Troubleshooting

### SSH Connection Issues
```bash
# Test SSH connection manually
ssh -o ConnectTimeout=10 root@cloudya.net 'echo "Connection successful"'

# Check SSH key format
ssh-keygen -l -f ~/.ssh/id_rsa
```

### Deployment Failures
```bash
# Check deployment logs on remote server
ssh root@cloudya.net 'cd /opt/infrastructure && tail -100 deployment.log'

# Check service status
ssh root@cloudya.net 'systemctl status docker'
ssh root@cloudya.net 'ps aux | grep -E "(nomad|vault|consul|traefik)"'
```

### Service Health Issues
```bash
# Check service endpoints
ssh root@cloudya.net 'curl -s http://localhost:8500/v1/status/leader'
ssh root@cloudya.net 'curl -s http://localhost:8200/v1/sys/health'
ssh root@cloudya.net 'curl -s http://localhost:8080/ping'
```

## Environment Configuration

Each environment has specific settings:

### Develop
- Vault: http://localhost:8200
- Auto-unseal enabled
- Development tokens
- Relaxed security settings

### Staging  
- Vault: https://localhost:8210
- Manual unseal required
- Production-like security
- Limited access

### Production
- Vault: https://localhost:8220
- Manual unseal required
- Maximum security
- Audit logging enabled
- Backup procedures required

## Rollback Procedures

### Emergency Rollback
```bash
# Stop services
ssh root@cloudya.net 'systemctl stop docker'

# Restore from backup
ssh root@cloudya.net 'cd /opt/infrastructure && ./scripts/restore-backup.sh <backup-id>'

# Restart services
ssh root@cloudya.net 'systemctl start docker'
```

### Planned Rollback
Use workflow dispatch with previous commit hash:
1. Go to Actions → Deploy Infrastructure
2. Select "Run workflow"
3. Choose environment and set "Force Bootstrap" if needed

## Monitoring

Post-deployment monitoring includes:
- Service health checks
- Port accessibility validation
- Process status verification
- Log collection and analysis
- Deployment artifact creation

## Support

For issues or questions:
1. Check GitHub Actions logs
2. Review deployment logs on remote server
3. Consult troubleshooting section above
4. Contact DevOps team if issues persist