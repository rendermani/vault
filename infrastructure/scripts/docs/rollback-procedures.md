# Rollback System Procedures

## Overview

The Cloudya Infrastructure Rollback System provides comprehensive deployment rollback capabilities with automatic failure detection, state management, and recovery procedures. The system consists of three main components:

1. **rollback-manager.sh** - Core rollback functionality and checkpoint management
2. **rollback-state-manager.sh** - Deployment state tracking and health monitoring  
3. **Integration with unified-bootstrap-systemd.sh** - Automatic rollback during deployment

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌────────────────────┐
│  Deployment     │    │  Rollback        │    │  State Management  │
│  Script         │──→ │  Manager         │──→ │  System            │
│                 │    │                  │    │                    │
│ • Creates       │    │ • Checkpoints    │    │ • Tracks Status    │
│   Checkpoints   │    │ • Rollbacks      │    │ • Health Monitor   │
│ • Monitors      │    │ • Verification   │    │ • History          │
│ • Auto-rollback │    │ • Recovery       │    │ • Export/Import    │
└─────────────────┘    └──────────────────┘    └────────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────────────┐
                    │    GitHub Workflows     │
                    │                         │
                    │ • Deployment Job        │
                    │ • Rollback Job          │
                    │ • Status Reporting      │
                    └─────────────────────────┘
```

## Quick Start

### 1. System Initialization

```bash
# Initialize rollback system
sudo ./scripts/rollback-manager.sh init

# Initialize state management
sudo ./scripts/rollback-state-manager.sh init
```

### 2. Create a Checkpoint Before Deployment

```bash
# Create checkpoint with custom name
sudo ./scripts/rollback-manager.sh checkpoint "pre-production-deployment"

# Create checkpoint with default name
sudo ./scripts/rollback-manager.sh checkpoint
```

### 3. Deploy with Automatic Rollback Protection

```bash
# Deploy with rollback enabled (default)
sudo ./scripts/unified-bootstrap-systemd.sh --environment production

# Deploy with custom checkpoint name
sudo ./scripts/unified-bootstrap-systemd.sh --environment production --checkpoint-name "v1.2.0-deployment"

# Deploy without rollback (not recommended)
sudo ./scripts/unified-bootstrap-systemd.sh --environment production --no-rollback
```

### 4. Manual Rollback if Needed

```bash
# List available checkpoints
sudo ./scripts/rollback-manager.sh list

# Rollback to specific checkpoint
sudo ./scripts/rollback-manager.sh rollback checkpoint-pre-production-deployment-20241225-123456

# Verify rollback success
sudo ./scripts/rollback-manager.sh status
```

## Detailed Procedures

### Checkpoint Management

#### Creating Checkpoints

```bash
# Standard checkpoint creation
sudo ./scripts/rollback-manager.sh checkpoint [name]

# Examples
sudo ./scripts/rollback-manager.sh checkpoint "pre-vault-upgrade"
sudo ./scripts/rollback-manager.sh checkpoint "before-security-hardening"
sudo ./scripts/rollback-manager.sh checkpoint
```

**What Gets Captured:**
- Systemd service states and configurations
- HashiCorp tool configurations (Nomad, Vault, Consul)
- Application data and volumes
- Network configurations and firewall rules
- SSL certificates and keys
- Docker containers and volumes
- Environment variables

#### Listing Checkpoints

```bash
# List all available checkpoints
sudo ./scripts/rollback-manager.sh list

# Example output:
Available Rollback Checkpoints:
================================
checkpoint-pre-deployment-develop-20241225-143022 - 20241225 14:30:22 - 45M [compressed]
checkpoint-pre-vault-upgrade-20241224-091445 - 20241224 09:14:45 - 32M
checkpoint-before-security-hardening-20241223-160330 - 20241223 16:03:30 - 28M [compressed]
```

#### Verifying Checkpoints

```bash
# Verify checkpoint integrity
sudo ./scripts/rollback-manager.sh verify checkpoint-pre-deployment-develop-20241225-143022

# Verify all checksums and component availability
```

### Rollback Procedures

#### Automatic Rollback

Automatic rollback is triggered when:
- Deployment script exits with error code
- Service health checks fail repeatedly
- Critical system components become unresponsive

```bash
# Automatic rollback happens transparently
# No manual intervention required
# System logs all actions to /var/log/cloudya/rollback.log
```

#### Manual Rollback

```bash
# Step 1: List available checkpoints
sudo ./scripts/rollback-manager.sh list

# Step 2: Verify checkpoint before rollback
sudo ./scripts/rollback-manager.sh verify CHECKPOINT_ID

# Step 3: Perform rollback
sudo ./scripts/rollback-manager.sh rollback CHECKPOINT_ID

# Step 4: Verify rollback success
sudo ./scripts/rollback-manager.sh status
sudo ./scripts/manage-services.sh status
```

#### Emergency Rollback

```bash
# Fastest rollback to latest checkpoint
sudo ./scripts/rollback-manager.sh auto-rollback "Emergency rollback requested"

# This uses the most recent checkpoint automatically
```

### State Management

#### Tracking Deployments

```bash
# Track new deployment
sudo ./scripts/rollback-state-manager.sh track-deployment "deployment-v1.2.0"

# Mark deployment as successful
sudo ./scripts/rollback-state-manager.sh mark-success "deployment-v1.2.0"

# Mark deployment as failed
sudo ./scripts/rollback-state-manager.sh mark-failure "deployment-v1.2.0"
```

#### Monitoring System Health

```bash
# Start continuous health monitoring
sudo ./scripts/rollback-state-manager.sh monitor-health --interval 60 --max-checks 5

# Check current health status
sudo ./scripts/rollback-state-manager.sh get-status DEPLOYMENT_ID
```

#### Deployment History

```bash
# List deployment history
sudo ./scripts/rollback-state-manager.sh list-deployments

# Example output:
Deployment History:
===================
ID                     Status      Started              Result  Environment
deployment-v1.2.0      completed   2024-12-25T14:30:22Z ✅      production
deployment-v1.1.9      failed      2024-12-24T09:14:45Z ❌      production
deployment-v1.1.8      completed   2024-12-23T16:03:30Z ✅      production

# Get last successful deployment
sudo ./scripts/rollback-state-manager.sh get-last-successful
```

### GitHub Workflow Integration

#### Normal Deployment with Rollback Protection

```yaml
# Trigger via GitHub Actions UI
# Select: environment, components, enable_rollback=true
```

#### Rollback via GitHub Workflow

```yaml
# Trigger via GitHub Actions UI
# Provide: rollback_checkpoint=checkpoint-id-here
```

#### Workflow Configuration

The rollback system integrates with GitHub Actions through:

1. **Environment Variables**: Rollback configuration passed to remote server
2. **Deployment Job**: Creates checkpoints and monitors for failures  
3. **Rollback Job**: Dedicated job for rollback operations
4. **State Reporting**: Detailed summaries in GitHub Actions output

## Configuration

### Rollback Manager Configuration

```bash
# Edit rollback-manager.sh variables
SNAPSHOT_RETENTION_DAYS=7        # How long to keep checkpoints
AUTO_ROLLBACK_ON_FAILURE=true   # Enable automatic rollback
ROLLBACK_TIMEOUT=300            # Rollback timeout in seconds
```

### State Manager Configuration

```bash
# Edit rollback-state-manager.sh variables
DEPLOYMENT_HISTORY_RETENTION=30  # Days to keep deployment history
FAILURE_DETECTION_INTERVAL=30    # Health check interval (seconds)
MAX_FAILURE_CHECKS=10           # Failures before rollback trigger
```

### Unified Bootstrap Integration

```bash
# Rollback options for unified-bootstrap-systemd.sh
--no-rollback              # Disable rollback system
--no-auto-rollback         # Disable automatic rollback
--checkpoint-name NAME     # Custom checkpoint name
```

## Troubleshooting

### Common Issues

#### Checkpoint Creation Fails

```bash
# Check disk space
df -h /var/rollback/cloudya

# Check permissions
ls -la /var/rollback/cloudya

# Check service status
sudo ./scripts/rollback-manager.sh status
```

#### Rollback Fails

```bash
# Check rollback logs
sudo tail -f /var/log/cloudya/rollback.log

# Verify checkpoint integrity
sudo ./scripts/rollback-manager.sh verify CHECKPOINT_ID

# Manual service restoration
sudo systemctl start consul
sudo systemctl start nomad
```

#### Service Not Starting After Rollback

```bash
# Check systemd status
sudo systemctl status consul
sudo systemctl status nomad

# Check service logs
sudo journalctl -u consul -f
sudo journalctl -u nomad -f

# Manual configuration restoration
sudo ./scripts/rollback-manager.sh rollback CHECKPOINT_ID
```

### Debug Mode

```bash
# Enable verbose logging
sudo ./scripts/rollback-manager.sh --verbose COMMAND
sudo ./scripts/rollback-state-manager.sh --verbose COMMAND

# Check all log files
sudo tail -f /var/log/cloudya/*.log
```

## Testing

### Test Suite

```bash
# Run rollback system tests (dry run)
sudo ./scripts/test-rollback-system.sh

# Run tests with actual operations (test environment only!)
sudo ./scripts/test-rollback-system.sh --real-run --environment test
```

### Manual Testing Scenarios

#### Test 1: Checkpoint and Rollback

```bash
# 1. Create checkpoint
sudo ./scripts/rollback-manager.sh checkpoint "test-checkpoint"

# 2. Make some changes (simulate deployment)
sudo systemctl stop consul

# 3. Perform rollback
CHECKPOINT_ID=$(sudo ./scripts/rollback-manager.sh list | head -1 | awk '{print $1}')
sudo ./scripts/rollback-manager.sh rollback $CHECKPOINT_ID

# 4. Verify services restored
sudo systemctl status consul
```

#### Test 2: Automatic Failure Detection

```bash
# 1. Start health monitoring
sudo ./scripts/rollback-state-manager.sh monitor-health --interval 10 --max-checks 3 &

# 2. Simulate failure
sudo systemctl stop consul
sudo systemctl stop nomad

# 3. Watch for automatic rollback trigger
tail -f /var/log/cloudya/rollback-state.log
```

## Security Considerations

### File Permissions

```bash
# Rollback directories (root only)
/var/rollback/cloudya/        # 700 (drwx------)
/var/rollback/cloudya/checkpoints/  # 700

# Log files (readable by admin group)  
/var/log/cloudya/            # 755 (drwxr-xr-x)
/var/log/cloudya/*.log       # 644 (-rw-r--r--)
```

### Sensitive Data Handling

- **Encryption**: Checkpoints can be encrypted using GPG
- **Token Cleanup**: Temporary tokens are securely wiped
- **Secret Masking**: Sensitive data masked in logs
- **Access Control**: Root privileges required for operations

### Backup and Recovery

```bash
# Export rollback state
sudo ./scripts/rollback-state-manager.sh export-state

# Backup checkpoints directory
sudo tar czf /backup/rollback-checkpoints-$(date +%Y%m%d).tar.gz /var/rollback/cloudya/checkpoints/

# Import rollback state
sudo ./scripts/rollback-state-manager.sh import-state /backup/state-backup.json
```

## Maintenance

### Regular Tasks

```bash
# Weekly: Clean up old checkpoints
sudo ./scripts/rollback-manager.sh cleanup

# Weekly: Clean up old deployment history  
sudo ./scripts/rollback-state-manager.sh cleanup-history

# Monthly: Export state backup
sudo ./scripts/rollback-state-manager.sh export-state

# Monthly: Verify checkpoint integrity
for checkpoint in $(sudo ./scripts/rollback-manager.sh list | awk '{print $1}'); do
    sudo ./scripts/rollback-manager.sh verify $checkpoint
done
```

### Monitoring

```bash
# Check rollback system health
sudo ./scripts/rollback-manager.sh status

# Check state management status
sudo ./scripts/rollback-state-manager.sh list-deployments

# Monitor logs
sudo tail -f /var/log/cloudya/rollback*.log
```

## Integration Examples

### Custom Deployment Script Integration

```bash
#!/bin/bash
# your-deployment-script.sh

# Create checkpoint before deployment
CHECKPOINT_ID=$(sudo /path/to/rollback-manager.sh checkpoint "pre-custom-deployment")

# Track deployment
sudo /path/to/rollback-state-manager.sh track-deployment "custom-deployment-$(date +%s)"

# Perform deployment
if ! your_deployment_function; then
    echo "Deployment failed, triggering rollback..."
    sudo /path/to/rollback-manager.sh rollback "$CHECKPOINT_ID"
    exit 1
fi

# Mark as successful
sudo /path/to/rollback-state-manager.sh mark-success "custom-deployment-$(date +%s)"
```

### Monitoring Integration

```bash
# Add to monitoring system
# Check rollback system health every 5 minutes
*/5 * * * * root /path/to/rollback-manager.sh status > /dev/null || alert "Rollback system unhealthy"

# Check for failed deployments hourly
0 * * * * root /path/to/rollback-state-manager.sh list-deployments | grep failed && alert "Failed deployments detected"
```

## Best Practices

### Development Environment
- Always test rollback procedures in development first
- Use descriptive checkpoint names
- Enable verbose logging during testing

### Staging Environment  
- Perform rollback drills regularly
- Test automatic failure detection
- Verify state management accuracy

### Production Environment
- Create checkpoints before all changes
- Monitor rollback system health
- Keep multiple successful checkpoints
- Document all rollback procedures
- Train team on emergency procedures

### Emergency Procedures
1. **Immediate Issues**: Use `auto-rollback` for fastest recovery
2. **Planned Rollback**: Verify checkpoint before rollback
3. **Partial Rollback**: Use component-specific restoration
4. **Communication**: Document rollback reason and results

## Support and Troubleshooting

### Log Locations
- **Rollback Manager**: `/var/log/cloudya/rollback.log`
- **State Manager**: `/var/log/cloudya/rollback-state.log`  
- **Deployment**: `/var/log/cloudya/deployment.log`
- **Test Results**: `/tmp/rollback-test-*.log`

### Key Commands Reference

```bash
# Core rollback operations
sudo ./scripts/rollback-manager.sh checkpoint [name]
sudo ./scripts/rollback-manager.sh rollback CHECKPOINT_ID
sudo ./scripts/rollback-manager.sh list
sudo ./scripts/rollback-manager.sh status

# State management
sudo ./scripts/rollback-state-manager.sh track-deployment ID
sudo ./scripts/rollback-state-manager.sh mark-success ID  
sudo ./scripts/rollback-state-manager.sh monitor-health

# Testing and validation
sudo ./scripts/test-rollback-system.sh
sudo ./scripts/rollback-manager.sh verify CHECKPOINT_ID

# Deployment integration
sudo ./scripts/unified-bootstrap-systemd.sh --environment ENV
```

This rollback system provides comprehensive protection for infrastructure deployments with automatic failure detection, state tracking, and recovery capabilities suitable for production environments.