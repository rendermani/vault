# HashiCorp Stack Implementation Plan

## Executive Summary

This implementation plan rebuilds the infrastructure using proven patterns from the existing repository. The approach uses:
- **Ansible** for bootstrapping (not complex bash scripts)
- **Terraform** for configuration (not manual setup)
- **Nomad Pack** for application deployment (not docker-compose)
- **Proper 6-phase deployment** avoiding circular dependencies

## Repository Analysis Summary

### Current Repository Strengths
✅ **Proven Bootstrap Pattern**: `/infrastructure/scripts/bootstrap.sh` shows proper dependency ordering  
✅ **Terraform Module Structure**: Comprehensive modules in `/traefik/terraform/modules/`  
✅ **Ansible Foundation**: Basic Ansible structure in `/traefik/ansible/`  
✅ **Environment Separation**: Clear dev/staging/prod separation  
✅ **Security Hardening**: Comprehensive security configurations  
✅ **Two-Phase Deployment Research**: Documented in vault-nomad-bootstrap-research.md  

### Key Architecture Decisions
- **Monorepo Approach**: Single source of truth with shared modules
- **Environment-First Organization**: Clear promotion paths
- **Dependency-Aware Bootstrap**: Vault → Nomad → Traefik ordering
- **Modern Security**: Workload identity over pre-shared tokens

## 6-Phase Implementation Plan

### Phase 1: Bootstrap with Ansible (Consul + Nomad without Vault)
**Goal**: Establish foundation infrastructure without circular dependencies

#### Ansible Playbooks Required
```yaml
# ansible/playbooks/01-system-bootstrap.yml
- name: System Bootstrap
  hosts: all
  roles:
    - system-hardening
    - docker-installation
    - consul-installation
    - nomad-installation-basic

# ansible/playbooks/02-consul-cluster.yml  
- name: Consul Cluster Setup
  hosts: consul_servers
  roles:
    - consul-cluster-init
    - consul-acl-bootstrap

# ansible/playbooks/03-nomad-cluster.yml
- name: Nomad Cluster Setup (No Vault Integration)
  hosts: nomad_servers
  roles:
    - nomad-cluster-init
    - nomad-acl-bootstrap
```

#### Key Components
- **System Hardening**: firewall, users, SSH keys
- **Consul Cluster**: Service discovery foundation
- **Basic Nomad**: Without Vault integration initially
- **TLS Certificates**: Let's Encrypt or internal CA

#### Deliverables
- [ ] `ansible/inventories/production/hosts.yml`
- [ ] `ansible/roles/system-hardening/`
- [ ] `ansible/roles/consul-installation/`
- [ ] `ansible/roles/nomad-installation-basic/`
- [ ] `ansible/group_vars/all.yml` with environment configs

### Phase 2: Manual Init (ACL Bootstrap, Vault Init/Unseal)
**Goal**: Initialize security systems that require manual intervention

#### Manual Steps Required
```bash
# 1. Bootstrap Consul ACLs
consul acl bootstrap

# 2. Bootstrap Nomad ACLs  
nomad acl bootstrap

# 3. Deploy Vault job to Nomad (using temporary tokens)
nomad job run jobs/vault-bootstrap.nomad

# 4. Initialize Vault
vault operator init -format=json > vault-keys.json

# 5. Unseal Vault
vault operator unseal <key1>
vault operator unseal <key2>  
vault operator unseal <key3>
```

#### Security Considerations
- **Bootstrap Tokens**: Store securely, rotate immediately after Phase 3
- **Vault Keys**: Distribute according to security policy
- **Network Access**: Limit to management network during bootstrap
- **Audit Logging**: Enable immediately after initialization

#### Deliverables
- [ ] `jobs/vault-bootstrap.nomad` - Temporary Vault deployment
- [ ] `scripts/manual-init.sh` - Guided initialization script
- [ ] `docs/bootstrap-security.md` - Security procedures
- [ ] Secure key storage procedures

### Phase 3: Terraform Configuration (Vault, ACLs, Policies)
**Goal**: Use Terraform to configure all services declaratively

#### Terraform Structure
```hcl
# terraform/
├── environments/
│   ├── production/
│   ├── staging/
│   └── develop/
├── modules/
│   ├── vault-config/
│   ├── nomad-config/
│   ├── consul-config/
│   └── security-policies/
└── shared/
    ├── variables.tf
    └── providers.tf
```

#### Key Configurations
```hcl
# terraform/modules/vault-config/main.tf
resource "vault_auth_backend" "nomad" {
  type = "jwt"
  path = "nomad-workload"
}

resource "vault_policy" "nomad_workload" {
  name   = "nomad-workload-policy"
  policy = templatefile("policies/nomad-workload.hcl", {
    environment = var.environment
  })
}

# terraform/modules/nomad-config/main.tf
resource "nomad_acl_policy" "vault_integration" {
  name = "vault-integration"
  policy = templatefile("policies/vault-integration.hcl", {
    vault_address = var.vault_address
  })
}
```

#### Deliverables
- [ ] Complete Terraform module structure
- [ ] Vault secret engines and policies
- [ ] Nomad ACL policies and roles
- [ ] Consul service definitions
- [ ] Cross-service authentication setup

### Phase 4: Enable Nomad-Vault Integration
**Goal**: Migrate from temporary tokens to workload identity

#### Migration Strategy
```bash
# 1. Configure Vault JWT auth for Nomad workloads
terraform apply -target=module.vault-config.vault_auth_backend.nomad

# 2. Update Nomad server configuration
ansible-playbook ansible/playbooks/04-vault-integration.yml

# 3. Test workload identity
nomad job run jobs/test-vault-integration.nomad

# 4. Migrate existing workloads
ansible-playbook ansible/playbooks/05-workload-migration.yml

# 5. Revoke temporary tokens
vault token revoke <bootstrap-token>
```

#### Workload Identity Configuration
```hcl
# jobs/example-app.nomad
job "example-app" {
  group "web" {
    task "app" {
      vault {
        policies      = ["app-policy"]
        change_mode   = "restart"
        role          = "app-role"
      }
    }
  }
}
```

#### Deliverables
- [ ] `ansible/playbooks/04-vault-integration.yml`
- [ ] Vault JWT auth configuration
- [ ] Updated Nomad server configs
- [ ] Workload identity test jobs
- [ ] Migration scripts for existing workloads

### Phase 5: Deploy Traefik with Nomad Pack
**Goal**: Deploy modern application gateway using Nomad Pack

#### Nomad Pack Configuration
```hcl
# packs/traefik/variables.hcl
variable "traefik_version" {
  description = "Traefik version to deploy"
  type        = string
  default     = "v3.0"
}

variable "vault_integration" {
  description = "Enable Vault integration for secrets"
  type        = bool
  default     = true
}

variable "dashboard_enabled" {
  description = "Enable Traefik dashboard"
  type        = bool
  default     = true
}
```

#### Traefik Job with Vault Integration
```hcl
# packs/traefik/templates/traefik.nomad.tpl
job "traefik" {
  type = "service"
  
  group "traefik" {
    count = [[ .traefik.count ]]
    
    task "traefik" {
      driver = "docker"
      
      vault {
        policies = ["traefik-policy"]
        role     = "traefik-role"
      }
      
      template {
        data = <<EOF
[[ with secret "secret/traefik/config" ]]
api:
  dashboard: true
  insecure: false

certificatesResolvers:
  letsencrypt:
    acme:
      email: [[ .Data.acme_email ]]
      storage: "consul"
      httpChallenge:
        entryPoint: web
[[ end ]]
EOF
        destination = "local/traefik.yml"
      }
      
      config {
        image = "traefik:[[ .traefik.version ]]"
        ports = ["web", "websecure", "traefik"]
        args = [
          "--configfile=local/traefik.yml",
          "--consul.endpoints=consul.service.consul:8500"
        ]
      }
    }
  }
}
```

#### Deliverables
- [ ] `packs/traefik/` - Complete Nomad Pack
- [ ] `packs/monitoring/` - Prometheus/Grafana pack
- [ ] `packs/ingress/` - Application ingress configurations
- [ ] Pack deployment automation
- [ ] Service discovery integration

### Phase 6: Testing and Validation
**Goal**: Comprehensive testing of the complete system

#### Test Categories

**1. Infrastructure Tests**
```bash
# Ansible infrastructure tests
molecule test

# Terraform validation
terraform plan -detailed-exitcode
terraform validate

# Nomad Pack validation  
nomad-pack plan packs/traefik
```

**2. Integration Tests**
```bash
# Vault-Nomad integration
./tests/vault-nomad-integration.sh

# Service discovery
./tests/consul-service-discovery.sh

# Load balancer routing
./tests/traefik-routing.sh

# Secret injection
./tests/vault-secret-injection.sh
```

**3. Security Tests**
```bash
# TLS certificate validation
./tests/tls-validation.sh

# ACL policy enforcement
./tests/acl-enforcement.sh

# Audit log verification
./tests/audit-logging.sh

# Vulnerability scanning
./tests/security-scan.sh
```

**4. Performance Tests**
```bash
# Load testing through Traefik
./tests/load-testing.sh

# Vault performance under load  
./tests/vault-performance.sh

# Nomad scheduling performance
./tests/nomad-scheduling.sh
```

#### Deliverables
- [ ] Complete test suite
- [ ] CI/CD pipeline integration
- [ ] Performance benchmarks
- [ ] Security validation reports
- [ ] Disaster recovery procedures

## Implementation Directory Structure

```
/src/infrastructure/
├── ansible/
│   ├── inventories/
│   │   ├── production/
│   │   ├── staging/
│   │   └── develop/
│   ├── playbooks/
│   │   ├── 01-system-bootstrap.yml
│   │   ├── 02-consul-cluster.yml
│   │   ├── 03-nomad-cluster.yml
│   │   ├── 04-vault-integration.yml
│   │   └── 05-workload-migration.yml
│   ├── roles/
│   │   ├── system-hardening/
│   │   ├── consul-installation/
│   │   ├── nomad-installation-basic/
│   │   └── vault-integration/
│   └── group_vars/
├── terraform/
│   ├── environments/
│   │   ├── production/
│   │   ├── staging/
│   │   └── develop/
│   ├── modules/
│   │   ├── vault-config/
│   │   ├── nomad-config/
│   │   ├── consul-config/
│   │   └── security-policies/
│   └── shared/
├── packs/
│   ├── traefik/
│   ├── monitoring/
│   └── applications/
├── jobs/
│   ├── vault-bootstrap.nomad
│   └── test-workloads/
├── tests/
│   ├── integration/
│   ├── security/
│   └── performance/
├── scripts/
│   ├── manual-init.sh
│   ├── deploy-phase.sh
│   └── validate-system.sh
└── docs/
    ├── bootstrap-security.md
    ├── troubleshooting.md
    └── operational-procedures.md
```

## Risk Mitigation

### Circular Dependency Risks
- **Phase 1-2 Separation**: Deploy Nomad without Vault initially
- **Temporary Tokens**: Use time-bounded tokens with immediate rotation
- **Rollback Procedures**: Each phase has rollback capability

### Security Risks
- **Bootstrap Token Exposure**: Minimize lifetime, secure storage
- **Network Isolation**: Bootstrap on management network only
- **Audit Logging**: Enable from Phase 2 onwards
- **Principle of Least Privilege**: Minimal permissions at each phase

### Operational Risks
- **Testing**: Comprehensive test suite before production
- **Documentation**: Detailed runbooks and procedures
- **Monitoring**: Full observability from Phase 1
- **Backup**: Automated backup at each phase

## Success Criteria

- [ ] All services deployed and healthy
- [ ] Zero manual configuration after Phase 2
- [ ] Complete secret management via Vault
- [ ] Modern workload identity (no static tokens)
- [ ] Comprehensive monitoring and alerting
- [ ] Disaster recovery procedures validated
- [ ] Security audit passing
- [ ] Performance benchmarks met

## Timeline Estimate

- **Phase 1**: 5-7 days (Ansible bootstrap)
- **Phase 2**: 2-3 days (Manual initialization)
- **Phase 3**: 7-10 days (Terraform configuration)
- **Phase 4**: 3-5 days (Vault integration)
- **Phase 5**: 5-7 days (Nomad Pack deployment)
- **Phase 6**: 7-10 days (Testing and validation)

**Total**: 4-6 weeks for complete implementation

## Next Steps

1. **Create Ansible roles** for system bootstrap
2. **Develop Terraform modules** for service configuration
3. **Build Nomad Packs** for application deployment
4. **Establish testing framework** for validation
5. **Document procedures** for operations team

This plan leverages the existing repository's proven patterns while modernizing the deployment approach to use industry best practices.