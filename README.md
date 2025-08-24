# HashiCorp Vault Infrastructure

Private repository for HashiCorp Vault deployment and configuration.

## Overview

This repository contains the infrastructure code for deploying HashiCorp Vault to cloudya.net with:
- Integrated Raft storage backend
- TLS encryption
- AppRole authentication
- Service-specific policies

## Deployment

Deployment is handled via GitHub Actions workflow:

1. Go to Actions tab
2. Select "Deploy Vault to cloudya.net"
3. Run workflow with desired action:
   - `deploy` - Deploy or update Vault
   - `init` - Initialize Vault (first time only)
   - `unseal` - Unseal Vault after restart

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       └── deploy.yml      # Deployment workflow
├── config/
│   └── vault.hcl          # Vault configuration
├── policies/              # Vault policies
├── scripts/              # Helper scripts
└── tests/               # Integration tests
```

## Security

- Never commit secrets to this repository
- Use GitHub Actions secrets for sensitive values
- Keep this repository private

## Dependencies

- GitHub Actions runner with SSH access to cloudya.net
- Vault 1.15.4+
- Root access on target server

## Related Repositories

- [rendermani/nomad](https://github.com/rendermani/nomad) - Nomad orchestration
- [rendermani/monitoring](https://github.com/rendermani/monitoring) - Monitoring stack
- [rendermani/traefik](https://github.com/rendermani/traefik) - Edge router