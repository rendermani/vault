# Infrastructure Deployment Scripts

This directory contains idempotent deployment scripts for the complete Vault infrastructure stack.

## Quick Start

### For GitHub Actions (Production)
```bash
# Complete deployment in one command
sudo ./deploy-all.sh --environment production --yes

# Or step by step
sudo ./install-consul.sh
sudo ./install-nomad.sh
./deploy-vault-job.sh --environment production --auto-init
./deploy-traefik-job.sh --environment production
./verify-deployment.sh --environment production
```

### For Development Testing
```bash
# Test what would be deployed (dry run)
./deploy-all.sh --dry-run --environment develop

# Deploy to development environment
sudo ./deploy-all.sh --environment develop --yes
```

## Scripts Overview

### Core Installation Scripts
- **`install-consul.sh`** - Idempotent Consul installation and configuration as systemd service
- **`install-nomad.sh`** - Idempotent Nomad installation and configuration as systemd service

### Job Deployment Scripts  
- **`deploy-vault-job.sh`** - Deploy Vault job to Nomad cluster with environment-specific configuration
- **`deploy-traefik-job.sh`** - Deploy Traefik job to Nomad cluster with Let's Encrypt automation

### Verification and Testing
- **`verify-deployment.sh`** - Comprehensive deployment verification with health checks
- **`test-scripts-simple.sh`** - Basic functionality tests for all scripts

### Orchestration
- **`deploy-all.sh`** - Master orchestration script that runs all deployments in correct order

### Utilities
- **`common.sh`** - Shared functions and utilities used by all scripts
- **`config-templates.sh`** - Configuration templates for all services

## Key Features

### Idempotent Operations
- All scripts can be run multiple times safely
- Check existing installations and services before making changes
- Version comparison for upgrades
- Service status validation

### Error Handling
- Comprehensive error checking with proper exit codes
- Rollback functionality for failed deployments
- Detailed logging with timestamps
- User confirmation prompts (can be overridden for CI/CD)

### Environment Support
- **Develop**: Basic setup with debug logging and minimal security
- **Staging**: Production-like with Let's Encrypt staging certificates
- **Production**: Full security, monitoring, and high availability

### Security Features
- Proper file permissions and ownership
- Secure user creation for services
- TLS certificate management
- Encryption key generation and rotation
- Security headers and hardening

## Environment Variables

### Version Control
```bash
export CONSUL_VERSION="1.17.0"       # Consul version to install
export NOMAD_VERSION="1.7.2"         # Nomad version to install
export VAULT_VERSION="1.17.6"        # Vault version to deploy
export TRAEFIK_VERSION="v3.2.3"      # Traefik version to deploy
```

### Configuration
```bash
export ENVIRONMENT="production"       # deployment environment
export DOMAIN_NAME="cloudya.net"      # primary domain
export ACME_EMAIL="admin@cloudya.net" # Let's Encrypt email
export NOMAD_NAMESPACE="default"      # Nomad namespace
export NOMAD_REGION="global"          # Nomad region
```

### Service Configuration
```bash
export CONSUL_DATACENTER="dc1"        # Consul datacenter name
export CONSUL_NODE_ROLE="server"      # server or client
export NOMAD_NODE_ROLE="both"         # server, client, or both
export AUTO_APPROVE="false"           # skip confirmation prompts
export DRY_RUN="false"                # show what would be done
```

## Usage Examples

### Complete Production Deployment
```bash
sudo ENVIRONMENT=production DOMAIN_NAME=example.com ACME_EMAIL=admin@example.com ./deploy-all.sh --yes
```

### Development Environment
```bash
sudo ./deploy-all.sh --environment develop --skip-traefik --yes
```

### Individual Service Deployment
```bash
# Deploy only Vault
./deploy-vault-job.sh --environment staging --auto-init

# Deploy only Traefik with staging certificates
./deploy-traefik-job.sh --environment staging --staging
```

### Verification and Testing
```bash
# Comprehensive verification
./verify-deployment.sh --environment production --verbose

# Skip external connectivity tests
./verify-deployment.sh --skip-external

# JSON output for automation
./verify-deployment.sh --output json > deployment-status.json
```

## File Structure

```
infrastructure/scripts/
├── README.md                    # This file
├── common.sh                    # Shared functions and utilities
├── config-templates.sh          # Configuration templates
├── install-consul.sh            # Consul installation
├── install-nomad.sh             # Nomad installation  
├── deploy-vault-job.sh          # Vault job deployment
├── deploy-traefik-job.sh        # Traefik job deployment
├── verify-deployment.sh         # Deployment verification
├── deploy-all.sh                # Master orchestration script
└── test-scripts-simple.sh       # Basic functionality tests
```

## Prerequisites

### System Requirements
- Linux system with systemd
- Root access (via sudo)
- Internet connectivity
- Minimum 2GB RAM, 20GB disk space

### Required Tools
- `bash` (version 4.0+)
- `curl` and `wget`
- `unzip` and `jq`
- `systemctl` (systemd)

### Network Requirements
- Ports 80, 443 (Traefik)
- Ports 4646-4648 (Nomad)
- Ports 8500, 8502 (Consul)
- Ports 8200-8201 (Vault)

## Deployment Flow

### Phase 1: Base Services
1. Install and configure Consul
2. Install and configure Nomad
3. Wait for cluster formation

### Phase 2: Application Services
1. Deploy Vault job to Nomad
2. Deploy Traefik job to Nomad
3. Wait for service availability

### Phase 3: Verification
1. Health checks for all services
2. TLS certificate validation
3. Network connectivity tests
4. Generate deployment report

## Troubleshooting

### Common Issues

**Scripts fail with permission errors:**
```bash
# Make sure you're running as root for system scripts
sudo ./install-consul.sh
sudo ./install-nomad.sh

# Job deployment scripts don't need root
./deploy-vault-job.sh --environment production
```

**Services don't start:**
```bash
# Check service status
systemctl status consul
systemctl status nomad

# View logs
journalctl -u consul -f
journalctl -u nomad -f
```

**Jobs fail to deploy:**
```bash
# Check Nomad connectivity
nomad node status

# View job status
nomad job status vault-production
nomad job status traefik

# Check allocation logs
nomad alloc logs <alloc-id>
```

**Certificate issues:**
```bash
# Check ACME storage
sudo ls -la /opt/nomad/volumes/traefik-certs/
sudo cat /opt/nomad/volumes/traefik-certs/acme.json | jq

# Test certificate provisioning
curl -I https://traefik.example.com
```

### Log Files
- **Deployment logs**: `../../logs/deployment.log`
- **Service logs**: `/var/log/consul/consul.log`, `/var/log/nomad/nomad.log`  
- **System logs**: `journalctl -u <service>`

### Getting Help
1. Run verification: `./verify-deployment.sh --verbose`
2. Check individual service status
3. Review log files for detailed error messages
4. Test network connectivity and DNS resolution

## GitHub Actions Integration

These scripts are designed to work with GitHub Actions CI/CD:

```yaml
- name: Deploy Infrastructure  
  run: |
    sudo ./infrastructure/scripts/deploy-all.sh \
      --environment production \
      --domain ${{ secrets.DOMAIN_NAME }} \
      --email ${{ secrets.ACME_EMAIL }} \
      --yes

- name: Verify Deployment
  run: |
    ./infrastructure/scripts/verify-deployment.sh \
      --environment production \
      --output json > deployment-status.json
```

## Security Considerations

### Production Checklist
- [ ] Change default passwords and API keys
- [ ] Configure proper TLS certificates
- [ ] Enable audit logging for all services
- [ ] Set up monitoring and alerting
- [ ] Configure automated backups
- [ ] Review and harden security policies
- [ ] Test disaster recovery procedures
- [ ] Complete compliance audit

### Best Practices
- Use strong encryption keys
- Rotate secrets regularly
- Monitor access logs
- Implement least privilege access
- Keep services updated
- Regular security scanning
- Backup critical data

---

For detailed information about individual scripts, run any script with the `--help` flag.# Trigger: Mon Aug 25 19:36:44 CEST 2025
