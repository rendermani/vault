# HashiCorp Stack Implementation

## Overview

This implementation rebuilds the infrastructure using proven patterns from the existing repository with modern best practices:

- **Ansible** for bootstrapping (not complex bash scripts)
- **Terraform** for configuration (not manual setup)  
- **Nomad Pack** for application deployment (not docker-compose)
- **Proper 6-phase deployment** avoiding circular dependencies

## Quick Start

### Prerequisites

```bash
# Install required tools
sudo apt update
sudo apt install -y ansible terraform

# Install HashiCorp tools
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt install -y consul nomad vault

# Install Nomad Pack
curl -L https://github.com/hashicorp/nomad-pack/releases/latest/download/nomad-pack_linux_amd64.zip -o nomad-pack.zip
unzip nomad-pack.zip && sudo mv nomad-pack /usr/local/bin/
```

### Phase-by-Phase Deployment

```bash
# Phase 1: Bootstrap with Ansible
./scripts/deploy-phase.sh 1 production

# Phase 2: Manual initialization  
./scripts/deploy-phase.sh 2 production

# Phase 3: Terraform configuration
./scripts/deploy-phase.sh 3 production

# Phase 4: Enable Vault integration
./scripts/deploy-phase.sh 4 production

# Phase 5: Deploy with Nomad Pack
./scripts/deploy-phase.sh 5 production

# Phase 6: Testing and validation
./scripts/deploy-phase.sh 6 production

# Or deploy all phases at once
./scripts/deploy-phase.sh all production
```

## Architecture

The implementation follows the proven dependency order:

```
Phase 1: System Bootstrap
├── System hardening
├── Docker installation
├── Consul cluster (service discovery)
└── Nomad cluster (basic, no Vault)

Phase 2: Manual Initialization  
├── Consul ACL bootstrap
├── Nomad ACL bootstrap
├── Vault deployment to Nomad
└── Vault initialization/unseal

Phase 3: Terraform Configuration
├── Vault secret engines & policies
├── Nomad ACL policies & roles  
├── Cross-service authentication
└── Environment-specific configs

Phase 4: Vault Integration
├── JWT auth configuration
├── Workload identity migration
├── Existing workload updates
└── Bootstrap token revocation

Phase 5: Application Deployment
├── Traefik via Nomad Pack
├── Monitoring stack deployment
├── Service discovery integration
└── Load balancer configuration

Phase 6: Validation
├── Infrastructure testing
├── Security validation
├── Performance benchmarks
└── Documentation generation
```

## Directory Structure

```
src/infrastructure/
├── ansible/             # Phase 1: System bootstrap
│   ├── inventories/     # Environment-specific hosts
│   ├── playbooks/       # Deployment playbooks  
│   └── roles/           # Reusable Ansible roles
├── terraform/           # Phase 3: Infrastructure as Code
│   ├── environments/    # Environment configs
│   └── modules/         # Reusable TF modules
├── packs/              # Phase 5: Nomad Pack deployments
│   ├── traefik/        # Modern reverse proxy
│   └── monitoring/     # Observability stack
├── jobs/               # Phase 2: Bootstrap jobs
├── tests/              # Phase 6: Validation suite
├── scripts/            # Deployment automation
└── docs/              # Implementation documentation
```

## Key Features

### ✅ Based on Proven Patterns
- Leverages existing `/infrastructure/scripts/bootstrap.sh` dependency logic
- Uses established Terraform module structure from `/traefik/terraform/`
- Implements security patterns from `/infrastructure/security/`
- Follows Ansible conventions from `/traefik/ansible/`

### 🚀 Modern Improvements  
- **Nomad Pack**: Replaces docker-compose for application deployment
- **Workload Identity**: Eliminates static token management
- **Declarative Config**: Terraform replaces manual setup
- **Comprehensive Testing**: Automated validation and reporting

### 🔒 Security First
- Two-phase bootstrap avoids circular dependencies
- Time-bounded tokens with automatic rotation
- Workload identity for secure service communication
- Comprehensive audit logging and monitoring

### 📊 Production Ready
- Environment separation (develop/staging/production)
- High availability configurations
- Disaster recovery procedures
- Performance monitoring and alerting

## Validation Against Existing Patterns

✅ **Bootstrap Order**: Matches `/infrastructure/scripts/bootstrap.sh` logic  
✅ **Terraform Structure**: Mirrors `/traefik/terraform/modules/` organization  
✅ **Ansible Patterns**: Follows `/traefik/ansible/` conventions  
✅ **Security Research**: Implements findings from `vault-nomad-bootstrap-research.md`  
✅ **Environment Configs**: Consistent with existing dev/staging/prod separation  
✅ **Nomad Jobs**: Based on patterns in `/infrastructure/nomad/jobs/`  

## Next Steps

1. **Review Implementation Plan**: See `/implementation-plan.md` for detailed specifications
2. **Customize Environment**: Update `ansible/inventories/` with your infrastructure  
3. **Configure Secrets**: Set up secure storage for bootstrap tokens and keys
4. **Run Phase 1**: Start with Ansible bootstrap for foundation services
5. **Monitor Progress**: Each phase includes validation and rollback procedures

## Support

- **Implementation Plan**: `/implementation-plan.md` - Complete technical details
- **Phase Scripts**: `/scripts/deploy-phase.sh` - Automated deployment  
- **Testing Suite**: `/tests/` - Comprehensive validation
- **Documentation**: `/docs/` - Operational procedures

This implementation provides a production-ready foundation while maintaining compatibility with existing infrastructure patterns.