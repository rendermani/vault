# Two-Phase Bootstrap Process: Solving the Vault-Nomad Circular Dependency

## Overview

This document explains the two-phase bootstrap process implemented to solve the circular dependency between Nomad and Vault in the infrastructure deployment.

## The Problem

The original deployment had a circular dependency:
- **Nomad** needs Vault tokens for secure operations
- **Vault** runs as a job ON Nomad
- During bootstrap, Nomad tries to connect to Vault (which doesn't exist yet)
- This causes the deployment to fail with "Vault token must be set" errors

```
┌─────────────────────────────────────────┐
│          CIRCULAR DEPENDENCY            │
├─────────────────────────────────────────┤
│  Nomad Config: vault { enabled = true } │
│             ↓                           │
│  Nomad tries to connect to Vault        │
│             ↓                           │
│  Vault doesn't exist yet! ❌           │
│             ↓                           │
│  Bootstrap FAILS                        │
└─────────────────────────────────────────┘
```

## The Solution: Two-Phase Bootstrap

### Phase 1: Initial Deployment (Vault Disabled)
1. Deploy Nomad with `vault { enabled = false }`
2. Use temporary bootstrap tokens for initial setup
3. Start Nomad successfully without Vault dependency

### Phase 2: Vault Integration (After Vault is Running)
1. Deploy Vault on the running Nomad cluster
2. Initialize Vault and create service tokens
3. Reconfigure Nomad to enable Vault integration
4. Reload Nomad with the new configuration

```
┌─────────────────────────────────────────┐
│           TWO-PHASE SOLUTION            │
├─────────────────────────────────────────┤
│ Phase 1: Bootstrap                      │
│   Nomad Config: vault { enabled=false } │
│   ✅ Nomad starts successfully          │
│                                         │
│ Phase 2: Integration                    │
│   ✅ Deploy Vault on Nomad             │
│   ✅ Reconfigure Nomad with Vault      │
│   ✅ Full integration achieved         │
└─────────────────────────────────────────┘
```

## Implementation Details

### Configuration Templates (`config-templates.sh`)

The `generate_nomad_config()` function now supports a `vault_bootstrap_phase` parameter:

```bash
# During bootstrap phase (vault_bootstrap_phase=true):
# vault {
#   enabled = false
#   # Will be enabled after Vault deployment
# }

# After bootstrap phase (vault_bootstrap_phase=false):
vault {
  enabled = true
  address = "https://127.0.0.1:8200"
  # ... integration settings
}
```

### Install Script (`install-nomad.sh`)

Added bootstrap phase awareness:
```bash
NOMAD_VAULT_BOOTSTRAP_PHASE="${NOMAD_VAULT_BOOTSTRAP_PHASE:-false}"

# Conditional Vault integration
if [[ "$VAULT_ENABLED" == "true" && "$NOMAD_VAULT_BOOTSTRAP_PHASE" != "true" ]]; then
    # Enable Vault integration
elif [[ "$NOMAD_VAULT_BOOTSTRAP_PHASE" == "true" ]]; then
    # Disable Vault during bootstrap
fi
```

### Unified Bootstrap Script (`unified-bootstrap-systemd.sh`)

Implements the two-phase process:

1. **Phase 1**: `deploy_nomad()`
   - Sets `NOMAD_VAULT_BOOTSTRAP_PHASE=true`
   - Deploys Nomad with Vault disabled
   - Verifies no Vault configuration exists

2. **Phase 2**: `enable_vault_integration()`
   - Called after Vault deployment
   - Reconfigures Nomad with Vault enabled
   - Validates the integration

### Reconfiguration Function

The `reconfigure_nomad_with_vault()` function handles the transition:

```bash
reconfigure_nomad_with_vault() {
    # 1. Validate Vault is accessible
    # 2. Backup current Nomad config
    # 3. Generate new config with Vault enabled
    # 4. Validate new configuration
    # 5. Apply configuration and reload Nomad
    # 6. Verify integration is working
}
```

## Usage

### Automatic (Recommended)
The bootstrap script handles the two-phase process automatically:

```bash
# This will automatically do both phases
./unified-bootstrap-systemd.sh --environment develop
```

### Manual (Advanced)
If you need to control each phase separately:

```bash
# Phase 1: Deploy Nomad with Vault disabled
export NOMAD_VAULT_BOOTSTRAP_PHASE=true
./unified-bootstrap-systemd.sh --components nomad

# Phase 2: Deploy Vault and enable integration
./unified-bootstrap-systemd.sh --components vault

# The script automatically calls reconfigure_nomad_with_vault()
```

## Verification

### Test the Implementation
```bash
./scripts/test-two-phase-bootstrap.sh
```

### Check Bootstrap Phase Status
```bash
# During Phase 1 - should show commented Vault config
sudo cat /etc/nomad/nomad.hcl | grep -A5 "Vault integration disabled"

# After Phase 2 - should show enabled Vault config  
sudo cat /etc/nomad/nomad.hcl | grep -A5 "vault {"
```

### Verify Integration
```bash
# Check Nomad status
nomad status

# Check Vault integration
vault status

# Check Nomad can reach Vault
nomad server members
```

## Benefits

1. **Eliminates Circular Dependency**: Clean bootstrap process
2. **Robust Error Handling**: Graceful fallback if reconfiguration fails
3. **Automatic Process**: No manual intervention required
4. **Backward Compatible**: Existing configurations still work
5. **Testable**: Comprehensive test suite validates the process

## Troubleshooting

### Bootstrap Phase Issues
If Phase 1 fails:
```bash
# Check Nomad logs
sudo journalctl -u nomad -f

# Verify Vault is disabled
sudo grep "vault {" /etc/nomad/nomad.hcl || echo "Vault correctly disabled"
```

### Integration Phase Issues
If Phase 2 fails:
```bash
# Check if Vault is accessible
curl -s http://localhost:8200/v1/sys/health

# Manual reconfiguration
source scripts/config-templates.sh
reconfigure_nomad_with_vault develop
```

### Rollback
If integration fails, the system automatically restores the previous configuration:
```bash
# Previous config is backed up as:
ls -la /etc/nomad/nomad.hcl.pre-vault.*
```

## Security Considerations

1. **Temporary Tokens**: Bootstrap tokens are securely cleaned up
2. **Vault Tokens**: Service tokens have appropriate TTL and policies
3. **Configuration Backup**: Previous configs are preserved for rollback
4. **Permission Management**: Proper file ownership and permissions maintained

## Future Enhancements

1. **Health Checks**: Monitor integration health continuously
2. **Token Rotation**: Automatic rotation of Vault tokens
3. **Multi-Environment**: Enhanced support for different environments
4. **Metrics**: Bootstrap process metrics and monitoring

---

This two-phase bootstrap process provides a robust, tested solution to the Vault-Nomad circular dependency while maintaining security and operational best practices.