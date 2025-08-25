# Vault Infrastructure

This directory contains the reorganized Vault infrastructure with multi-environment support and Traefik integration.

## Directory Structure

```
infrastructure/vault/
├── config/
│   ├── vault.hcl                 # Main Vault configuration
│   └── environments/             # Environment-specific configurations
│       ├── develop.hcl           # Development environment
│       ├── staging.hcl           # Staging environment
│       └── production.hcl        # Production environment
├── policies/
│   ├── admin.hcl                 # Administrator policy
│   ├── ci-cd.hcl                 # CI/CD pipeline policy
│   ├── developer.hcl             # Developer access policy
│   ├── operations.hcl            # Operations team policy
│   ├── traefik-policy.hcl        # Traefik service policy
│   └── environments/             # Environment-specific policies
│       ├── develop-policy.hcl    # Development environment policy
│       ├── staging-policy.hcl    # Staging environment policy
│       └── production-policy.hcl # Production environment policy
├── scripts/
│   ├── setup-secret-paths.sh     # Initialize secret paths and policies
│   ├── validate-policies.sh      # Validate policies and test access
│   ├── integrate-traefik.sh      # Complete Traefik-Vault integration
│   └── [other vault scripts...]
└── [other vault directories...]
```

## Quick Start Guide

### 1. Initialize Everything
```bash
cd infrastructure/vault/scripts
./setup-secret-paths.sh
```

### 2. Validate Setup
```bash
./validate-policies.sh
```

### 3. Integrate with Traefik
```bash
ENVIRONMENT=develop ./integrate-traefik.sh
```

### 4. Start Vault (Environment-Specific)
```bash
# Development
vault server -config=../config/environments/develop.hcl

# Production  
vault server -config=../config/environments/production.hcl
```

## Secret Paths Structure

The following secret paths have been established for Traefik and multi-environment support:

### Traefik Secrets

- `secret/traefik/dashboard/credentials` - Dashboard username/password
- `secret/traefik/certificates/*` - SSL/TLS certificates
- `secret/traefik/config/*` - Traefik configuration secrets
- `secret/traefik/auth/*` - API keys and middleware secrets

### Environment-Specific Paths

- `secret/traefik/environments/{develop,staging,production}/*` - Environment-specific Traefik configs
- `secret/environments/{develop,staging,production}/*` - General environment secrets
- `secret/database/{develop,staging,production}/*` - Database credentials
- `secret/services/{develop,staging,production}/*` - Service configurations

## Policies

### Traefik Policy

The `traefik-policy.hcl` provides Traefik with access to:
- Dashboard credentials (read-only)
- SSL certificates (read-only)
- Configuration secrets (read-only)
- Environment-specific secrets (read-only)

### Environment Policies

- **Development Policy**: Full CRUD access to development secrets
- **Staging Policy**: Read/limited update access to staging secrets
- **Production Policy**: Read-only access to production secrets with strict audit logging

## Environment Configuration

### Development

- TLS disabled for simplicity
- Debug logging enabled
- Shorter lease times
- Local socket permissions relaxed

### Staging

- TLS enabled with Let's Encrypt staging certificates
- Production-like configuration
- Moderate logging level
- Auto-unseal configuration ready

### Production

- Maximum security configuration
- TLS 1.3 only with mutual authentication
- Minimal logging for security
- HSM/KMS auto-unseal required
- Strict network access controls

## Traefik Integration

### Service Token

A service token for Traefik is automatically created and stored at:
`secret/traefik/auth/service_token`

### Configuration Example

Add to your Traefik configuration:

```yaml
# traefik.yml
experimental:
  plugins:
    vault-plugin:
      modulename: github.com/traefik/traefik-vault-plugin
      version: v1.0.0

providers:
  vault:
    endpoints:
      - "https://vault.cloudya.net:8200"
    token: "{{ vault_token }}"  # Use service token
    pollInterval: "30s"
```

### Dashboard Credentials

Retrieve dashboard credentials:

```bash
# Get username
vault kv get -field=username secret/traefik/dashboard/credentials

# Get password
vault kv get -field=password secret/traefik/dashboard/credentials
```

## Security Considerations

1. **Access Control**: Environment policies enforce strict separation
2. **Audit Logging**: All production access is logged
3. **Token Management**: Service tokens have appropriate TTL and policies
4. **Network Security**: Production requires mutual TLS
5. **Secret Rotation**: Dashboard and service credentials should be rotated regularly

## Monitoring

Monitor Vault health and performance:

```bash
# Check cluster health
vault status

# Monitor metrics (if Prometheus enabled)
curl http://vault.cloudya.net:8200/v1/sys/metrics

# Review audit logs
tail -f /var/log/vault/audit.log
```

## Summary

**Total Policy Files Created**: 12 HCL files
- 4 Main policies (admin, ci-cd, developer, operations)  
- 1 Traefik policy
- 3 Environment-specific policies
- 4 Environment configurations

**Key Script Files**:
- `setup-secret-paths.sh` - Initialize secret paths and policies
- `validate-policies.sh` - Comprehensive validation and testing
- `integrate-traefik.sh` - Complete Traefik-Vault integration

## Migration Notes

This reorganization moves Vault configuration from the root directory to `infrastructure/vault/` to improve organization and support multi-environment deployments. All existing functionality is preserved with enhanced security and environment separation.

### Migration Checklist
- ✅ All vault files moved to infrastructure/vault/
- ✅ Environment-specific configurations created
- ✅ Traefik policies and integration scripts ready
- ✅ Secret paths structure defined
- ✅ Validation scripts created
- ✅ Documentation updated