# 🚀 Cloudya Vault Infrastructure Deployment Guide

This guide explains how to deploy the complete Cloudya Vault infrastructure using our comprehensive deployment automation system.

## 📋 Quick Start

### Prerequisites

1. **GitHub CLI**: Install and authenticate with GitHub
   ```bash
   # Install GitHub CLI
   brew install gh  # macOS
   # or
   curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
   
   # Authenticate
   gh auth login
   ```

2. **Required tools**: `jq`, `curl`, `ssh`
   ```bash
   brew install jq curl  # macOS
   # or
   sudo apt-get install jq curl  # Ubuntu/Debian
   ```

3. **SSH access** to the target server (cloudya.net)

### 🎯 One-Click Deployments

```bash
# Development environment (quick and easy)
./scripts/quick-deploy.sh dev

# Staging environment
./scripts/quick-deploy.sh staging

# Production environment (with safety checks)
./scripts/quick-deploy.sh production

# Deploy only applications (skip infrastructure)
./scripts/quick-deploy.sh apps-only develop

# Perform dry run to test changes
./scripts/quick-deploy.sh dry-run

# Check system health
./scripts/quick-deploy.sh health
```

## 🛠️ Deployment Script Usage

### Main Deployment Script

The main deployment script `deploy.sh` provides comprehensive control over the deployment process:

```bash
./deploy.sh [OPTIONS]
```

#### Common Usage Examples

```bash
# Full development deployment with auto-approval and wait
./deploy.sh --environment develop --phases all --auto-approve --wait

# Staging deployment with manual approval
./deploy.sh --environment staging --phases all --wait

# Production deployment (requires manual confirmation)
./deploy.sh --environment production --phases all --wait

# Bootstrap only (for new servers)
./deploy.sh --environment develop --phases bootstrap-only --force-bootstrap

# Deploy only Terraform configuration
./deploy.sh --environment staging --phases terraform-only

# Deploy only Nomad applications
./deploy.sh --environment develop --phases nomad-packs-only

# Custom phases (bootstrap + applications, skip terraform)
./deploy.sh --phases custom --custom-phases phase1,phase6

# Dry run (no actual changes)
./deploy.sh --environment develop --dry-run

# Check deployment status
./deploy.sh --status

# View deployment logs
./deploy.sh --logs

# Rollback deployment
./deploy.sh --environment develop --rollback
```

#### Deployment Options

| Option | Description | Default |
|--------|-------------|---------|
| `-e, --environment` | Target environment (develop/staging/production) | develop |
| `-p, --phases` | Deployment phases to execute | all |
| `--custom-phases` | Custom phases for 'custom' option | - |
| `-f, --force-bootstrap` | Force complete system bootstrap (DESTRUCTIVE) | false |
| `-a, --auto-approve` | Auto-approve all deployment steps | false |
| `-d, --dry-run` | Perform dry run without actual changes | false |
| `-c, --continue-on-failure` | Continue execution even if a phase fails | false |
| `-t, --timeout` | Deployment timeout in minutes | 60 |
| `-w, --wait` | Wait for deployment completion | false |
| `--rollback` | Rollback to previous deployment state | - |
| `--status` | Show deployment status | - |
| `--logs` | Show deployment logs | - |

## 🏗️ Deployment Phases

### Phase 1: Ansible Bootstrap
- **Purpose**: System hardening, base package installation, HashiCorp tools setup
- **Includes**: Security configuration, firewall setup, Docker, Consul, Nomad
- **When to use**: New servers, major system updates, security updates

```bash
./deploy.sh --phases bootstrap-only --environment develop
```

### Phase 3: Terraform Configuration
- **Purpose**: Infrastructure configuration management
- **Includes**: Environment-specific configurations, state management
- **When to use**: Configuration changes, infrastructure updates

```bash
./deploy.sh --phases terraform-only --environment staging
```

### Phase 6: Nomad Pack Deployment
- **Purpose**: Application deployment using Nomad Packs
- **Includes**: Vault, Traefik, monitoring stack, custom applications
- **When to use**: Application updates, service deployments

```bash
./deploy.sh --phases nomad-packs-only --environment develop
```

### Combined Phases
- **all**: Execute all phases (complete deployment)
- **infrastructure-only**: Execute Phase 1 + 3 (skip applications)
- **custom**: Execute specific phases using `--custom-phases`

## 🎛️ Environment-Specific Configurations

### Development Environment
- **Purpose**: Development and testing
- **Safety**: Low (allows force bootstrap, auto-approve)
- **Features**: Quick deployments, minimal safety checks

### Staging Environment  
- **Purpose**: Pre-production testing
- **Safety**: Medium (requires manual approval for destructive operations)
- **Features**: Production-like environment, thorough testing

### Production Environment
- **Purpose**: Live production services
- **Safety**: High (requires explicit confirmation for all operations)
- **Features**: Maximum safety checks, maintenance window validation, manual approvals

## 🔍 Monitoring and Management

### Health Checks

```bash
# Comprehensive health check
./scripts/health-check.sh

# Check only services
./scripts/health-check.sh --services-only

# Check only network connectivity
./scripts/health-check.sh --network-only
```

### Deployment Status

```bash
# View recent workflow runs
./deploy.sh --status

# View specific deployment logs
./deploy.sh --logs

# View logs for specific run
./deploy.sh --logs <run-id>
```

### Service Management

```bash
# SSH into server
ssh root@cloudya.net

# Check service status
systemctl status consul nomad vault traefik

# View service logs
journalctl -u consul -f
journalctl -u nomad -f

# Check Nomad jobs
nomad job status

# Check Consul services
consul catalog services
```

## 🔄 Rollback Procedures

### Automated Rollback

```bash
# Interactive rollback menu
./scripts/quick-deploy.sh rollback

# Direct rollback
./deploy.sh --environment staging --rollback
```

### Manual Rollback Steps

1. **Stop Current Services**
   ```bash
   ssh root@cloudya.net
   systemctl stop nomad consul vault traefik
   ```

2. **Check Previous State**
   ```bash
   cat /opt/infrastructure/state/deployment-complete
   ```

3. **Restore Configuration**
   - Restore previous Terraform state
   - Restore previous service configurations
   - Restore previous Nomad jobs

4. **Restart Services**
   ```bash
   systemctl start consul nomad
   # Wait for cluster to be ready, then start other services
   ```

## 🚨 Emergency Procedures

### Complete System Recovery

If the system is completely broken:

1. **Force Bootstrap** (DESTRUCTIVE)
   ```bash
   ./deploy.sh --environment develop --phases bootstrap-only --force-bootstrap --auto-approve
   ```

2. **Rebuild Infrastructure**
   ```bash
   ./deploy.sh --environment develop --phases infrastructure-only --auto-approve
   ```

3. **Redeploy Applications**
   ```bash
   ./deploy.sh --environment develop --phases nomad-packs-only --auto-approve
   ```

### Service-Specific Recovery

#### Consul Recovery
```bash
ssh root@cloudya.net
systemctl stop consul
rm -rf /opt/consul/data/*  # DESTRUCTIVE
systemctl start consul
```

#### Nomad Recovery  
```bash
ssh root@cloudya.net
systemctl stop nomad
# Jobs will be rescheduled when Nomad starts
systemctl start nomad
```

## 📊 Troubleshooting

### Common Issues

1. **SSH Connection Failed**
   ```bash
   # Check SSH key and connectivity
   ssh -v root@cloudya.net
   ```

2. **Workflow Trigger Failed**
   ```bash
   # Check GitHub authentication
   gh auth status
   gh auth refresh
   ```

3. **Services Not Starting**
   ```bash
   # Check service logs
   ssh root@cloudya.net journalctl -u consul -u nomad --since "10 minutes ago"
   ```

4. **Nomad Jobs Failing**
   ```bash
   # Check job status and allocations
   ssh root@cloudya.net
   nomad job status <job-name>
   nomad alloc logs <alloc-id>
   ```

### Debug Mode

Enable verbose logging for detailed troubleshooting:

```bash
./deploy.sh --environment develop --verbose --dry-run
```

### Log Analysis

All deployment operations are logged:

```bash
# View deployment script logs
tail -f /tmp/cloudya-deploy-*.log

# View GitHub Actions logs
gh run view <run-id> --log

# View system logs on server
ssh root@cloudya.net journalctl -f
```

## 🔐 Security Considerations

### Production Deployments
- Always use `--wait` to monitor deployments
- Never use `--auto-approve` for production
- Review changes in staging first
- Deploy during maintenance windows
- Have rollback plan ready

### Secrets Management
- All secrets stored in GitHub Secrets
- Vault integration for runtime secrets
- No secrets in code or logs
- SSH keys properly managed

### Access Control
- GitHub repository permissions
- SSH key management
- Server-level access controls
- Service account isolation

## 📚 Additional Resources

### GitHub Actions Workflows
- `unified-deployment-orchestration.yml`: Main orchestration workflow
- `phase1-ansible-bootstrap.yml`: System bootstrap
- `phase3-terraform-config.yml`: Infrastructure configuration
- `phase6-nomad-pack-deploy.yml`: Application deployment
- `rollback-management.yml`: Rollback procedures

### Configuration Files
- `ansible/`: Ansible playbooks and roles
- `terraform/`: Terraform configurations
- `src/nomad-packs/`: Nomad Pack definitions
- `monitoring/`: Monitoring and alerting configs

### Support
- Check GitHub Issues for known problems
- Review workflow logs in GitHub Actions
- Monitor system health with health-check script
- Contact platform team for complex issues

---

## 🎯 Quick Reference

```bash
# Most common operations
./scripts/quick-deploy.sh dev          # Deploy to development
./scripts/quick-deploy.sh staging      # Deploy to staging  
./scripts/quick-deploy.sh production   # Deploy to production
./scripts/quick-deploy.sh health       # Health check
./scripts/quick-deploy.sh status       # Deployment status
./scripts/quick-deploy.sh rollback     # Interactive rollback

# Advanced operations
./deploy.sh --environment develop --phases all --auto-approve --wait
./deploy.sh --environment production --dry-run
./deploy.sh --phases custom --custom-phases phase1,phase6
./deploy.sh --environment staging --rollback
```

**Remember**: Always test in development first, then staging, then production! 🚀