# HashiCorp Infrastructure Cleanup and Restoration Guide

This guide explains how to safely remove and restore HashiCorp Vault, Nomad, and Consul installations using the provided cleanup and restoration scripts.

## Overview

The cleanup and restoration system consists of two complementary scripts:

- **`cleanup-hashicorp.sh`**: Safely removes HashiCorp installations while preserving backups
- **`restore-hashicorp.sh`**: Restores HashiCorp installations from cleanup backups

## Safety Features

### Backup Protection
- **Comprehensive backups** created before any removal
- **Timestamped backup directories** prevent overwrites
- **Organized backup structure** for easy navigation
- **Detailed logging** of all operations

### Confirmation Requirements
- **Interactive confirmations** before destructive actions
- **Dry-run mode** to preview changes
- **Force mode** for automated environments
- **Backup-only mode** for safety testing

### Verification Systems
- **Pre-cleanup validation** of system state
- **Post-cleanup verification** of removal completion
- **Restoration validation** of backup integrity
- **Detailed reporting** of all operations

## Cleanup Script Usage

### Basic Usage

```bash
# Interactive cleanup with confirmations
sudo ./scripts/cleanup-hashicorp.sh

# Preview what would be cleaned up
sudo ./scripts/cleanup-hashicorp.sh --dry-run

# Automated cleanup without prompts
sudo ./scripts/cleanup-hashicorp.sh --force

# Only create backups without removing anything
sudo ./scripts/cleanup-hashicorp.sh --backup-only
```

### What Gets Removed

#### Systemd Services
- Stops running services: `vault`, `nomad`, `consul`
- Disables services from auto-start
- Removes service files from `/etc/systemd/system/`
- Reloads systemd daemon

#### Binary Files
- Removes binaries from:
  - `/usr/local/bin/` (vault, nomad, consul)
  - `/usr/bin/` (vault, nomad, consul)

#### Configuration Directories
- `/etc/vault.d/` - Vault configuration
- `/etc/nomad.d/` - Nomad configuration  
- `/etc/consul.d/` - Consul configuration

#### Data Directories
- `/var/lib/vault/` - Vault data
- `/var/lib/nomad/` - Nomad data
- `/var/lib/consul/` - Consul data
- `/opt/vault/` - Vault installation
- `/opt/nomad/` - Nomad installation
- `/opt/consul/` - Consul installation

#### Repository Sources
- APT sources: `/etc/apt/sources.list.d/hashicorp.list`
- YUM repos: `/etc/yum.repos.d/hashicorp.repo`
- Updates package databases after removal

#### User Accounts
- System users: `vault`, `nomad`, `consul`
- System groups: `vault`, `nomad`, `consul`

### Backup Structure

Backups are created in timestamped directories:
```
~/hashicorp-cleanup-backup-YYYYMMDD-HHMMSS/
├── services/           # Systemd service files
├── config/            # Configuration directories
├── data/              # Data directories and /opt installations
├── binaries/          # Binary files
├── repositories/      # APT/YUM repository files
├── cleanup.log        # Detailed operation log
└── cleanup-report.txt # Summary report
```

## Restoration Script Usage

### Basic Usage

```bash
# Interactive restoration with backup selection
sudo ./scripts/restore-hashicorp.sh

# List available backup directories
sudo ./scripts/restore-hashicorp.sh --list

# Restore from specific backup directory
sudo ./scripts/restore-hashicorp.sh ~/hashicorp-cleanup-backup-20250825-143022
```

### What Gets Restored

#### Service Files
- Systemd service files to `/etc/systemd/system/`
- Reloads systemd daemon
- **Note**: Services are NOT automatically started

#### Binary Files
- HashiCorp binaries to original locations
- Sets executable permissions (755)

#### Directory Structure
- Configuration directories to `/etc/`
- Data directories to `/var/lib/` and `/opt/`
- Sets appropriate permissions and ownership

#### Repository Sources
- APT/YUM repository configurations
- Updates package databases after restoration

#### User Accounts
- Recreates system users and groups
- Sets appropriate home directories

### Post-Restoration Steps

After successful restoration, manually start services as needed:

```bash
# Enable and start Vault
sudo systemctl enable vault
sudo systemctl start vault
sudo systemctl status vault

# Enable and start Nomad
sudo systemctl enable nomad
sudo systemctl start nomad
sudo systemctl status nomad

# Enable and start Consul
sudo systemctl enable consul
sudo systemctl start consul
sudo systemctl status consul
```

## Safety Best Practices

### Before Cleanup
1. **Stop critical applications** that depend on HashiCorp services
2. **Document current configurations** and service states
3. **Test with `--dry-run`** to understand impact
4. **Ensure sufficient disk space** for backups
5. **Run during maintenance windows** for production systems

### During Operations
1. **Monitor logs** in real-time if needed
2. **Keep backup locations** accessible
3. **Don't interrupt operations** once started
4. **Verify backup completeness** before proceeding

### After Operations
1. **Verify service removal/restoration** with system commands
2. **Test application functionality** that depends on services  
3. **Review logs and reports** for any issues
4. **Keep backups** until confident in the results
5. **Update documentation** and runbooks

## Common Use Cases

### Development Environment Reset
```bash
# Quick cleanup for fresh installation
sudo ./scripts/cleanup-hashicorp.sh --force
# Then install fresh versions
```

### Production Migration
```bash
# Create backup without removal
sudo ./scripts/cleanup-hashicorp.sh --backup-only
# Test restoration on staging
sudo ./scripts/restore-hashicorp.sh
# Proceed with production after validation
```

### Troubleshooting Corrupted Installation
```bash
# Preview what would be cleaned
sudo ./scripts/cleanup-hashicorp.sh --dry-run
# Remove problematic installation
sudo ./scripts/cleanup-hashicorp.sh
# Restore from known good backup
sudo ./scripts/restore-hashicorp.sh
```

## Troubleshooting

### Common Issues

#### Permission Denied Errors
- Ensure running with `sudo` for system modifications
- Check file system permissions on backup directories

#### Service Won't Stop
- Scripts handle forceful termination of stuck processes
- Check for dependency services that may prevent shutdown

#### Incomplete Backups
- Verify sufficient disk space before starting
- Check backup directory contents against cleanup report

#### Restoration Failures
- Validate backup directory structure before restoration
- Ensure no conflicting installations are present

### Recovery Procedures

#### If Cleanup Fails Midway
1. Check the log file for specific errors
2. Manually verify what was actually removed
3. Use restoration script to recover from backup
4. Address underlying issues before retrying

#### If Restoration Fails Midway  
1. Check system state with verification commands
2. Review restoration logs for specific failures
3. Manually complete any remaining restoration steps
4. Test service functionality before declaring success

### Log Analysis

Both scripts provide detailed logging:

```bash
# View cleanup log
tail -f ~/hashicorp-cleanup-backup-*/cleanup.log

# Check for errors in restoration
grep -i error ~/hashicorp-cleanup-backup-*/cleanup.log

# Review operations summary
cat ~/hashicorp-cleanup-backup-*/cleanup-report.txt
```

## Integration with Infrastructure

### CI/CD Pipeline Integration
```yaml
- name: Clean Environment
  run: |
    sudo /path/to/cleanup-hashicorp.sh --force
    
- name: Deploy Fresh Installation  
  run: |
    # Your installation commands here
```

### Monitoring Integration
- Monitor backup directory sizes
- Alert on cleanup/restoration failures
- Track service availability during operations

### Documentation Updates
- Update runbooks after major changes
- Document any custom configurations lost in cleanup
- Maintain restoration testing procedures

## Security Considerations

### Backup Security
- Backup directories may contain sensitive configuration data
- Secure backup locations with appropriate permissions
- Consider encryption for long-term backup storage

### Service Account Management
- User/group recreation uses system defaults
- Review and update service account permissions after restoration
- Verify service isolation after restoration

### Network Security
- Services are restored but not started automatically
- Review firewall rules before starting restored services
- Update security configurations as needed

## Support and Maintenance

### Regular Testing
- Test cleanup and restoration procedures quarterly
- Validate backups on different systems
- Update scripts as HashiCorp tools evolve

### Version Compatibility
- Scripts designed for current HashiCorp tool versions
- Test with new versions before production use
- Update backup strategies for new configuration formats

### Community Support
- Report issues through standard infrastructure channels
- Contribute improvements back to the codebase
- Share lessons learned with the team

---

## Quick Reference

### Cleanup Commands
```bash
sudo ./scripts/cleanup-hashicorp.sh --dry-run    # Preview
sudo ./scripts/cleanup-hashicorp.sh             # Interactive  
sudo ./scripts/cleanup-hashicorp.sh --force     # Automated
sudo ./scripts/cleanup-hashicorp.sh --backup-only # Backup only
```

### Restoration Commands
```bash
sudo ./scripts/restore-hashicorp.sh --list      # List backups
sudo ./scripts/restore-hashicorp.sh             # Interactive
sudo ./scripts/restore-hashicorp.sh /path/to/backup # Specific backup
```

### Verification Commands
```bash
systemctl status vault nomad consul             # Service status
which vault nomad consul                        # Binary locations
ls -la /etc/{vault.d,nomad.d,consul.d}         # Config directories
ls -la /var/lib/{vault,nomad,consul}            # Data directories
```