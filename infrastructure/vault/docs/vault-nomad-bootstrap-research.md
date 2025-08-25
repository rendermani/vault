# Vault-Nomad Bootstrap Pattern Research

## Executive Summary

This document analyzes the bootstrap pattern for deploying Vault on Nomad infrastructure, addressing the circular dependency challenge while maintaining complete environment separation. The research covers security implications, project structure options, and scalability considerations for multi-environment deployments.

## 1. Bootstrap Pattern Analysis

### The Circular Dependency Problem

When deploying Vault on Nomad, a classic "chicken and egg" problem occurs:

1. **Nomad needs Vault tokens** for authentication and secret management integration
2. **Vault needs to be running** somewhere to provide those tokens  
3. **Running Vault on Nomad** requires Nomad to already have access to Vault

### Recommended Bootstrap Solutions

#### 1. Two-Phase Deployment Approach (RECOMMENDED)

**Phase 1: Temporary Bootstrap**
```bash
# Step 1: Install Nomad with temporary tokens
nomad acl bootstrap  # Generates bootstrap token (management type)

# Step 2: Create Vault-specific policy and token
vault policy write nomad-server - <<EOF
path "auth/token/create/nomad-cluster" {
  capabilities = ["update"]
}
path "auth/token/roles/nomad-cluster" {
  capabilities = ["read"]
}
EOF

# Step 3: Generate temporary token for Vault integration
vault token create -policy=nomad-server -period=72h -orphan
```

**Phase 2: Production Migration**
```bash
# Step 4: Deploy Vault on Nomad using temporary token
nomad job run vault.nomad.hcl

# Step 5: Configure Vault and migrate tokens
vault auth enable jwt
vault write auth/jwt/config jwt_validation_pubkeys=@/path/to/nomad-jwt.pem

# Step 6: Rotate and revoke temporary tokens
vault token revoke <temporary-token>
```

#### 2. Workload Identity Migration (MODERN APPROACH)

Starting in Nomad 1.7+, workload identities eliminate the need for pre-shared tokens:

```hcl
# nomad agent configuration
server {
  # Enable workload identity
  default_scheduler_config {
    preemption_config {
      system_scheduler_enabled = true
    }
  }
}

vault {
  enabled          = true
  address          = "https://vault.service.consul:8200"
  jwt_auth_backend_path = "jwt"
  
  # No token required with workload identity
  create_from_role = "nomad-cluster"
}
```

### Security Implications Analysis

#### Bootstrap Token Risks
- **Management Token Exposure**: Bootstrap tokens have full management privileges
- **Token Persistence**: Temporary tokens may persist beyond intended lifecycle
- **Network Transit**: Token transmission during bootstrap phase

#### Mitigation Strategies
1. **Time-bounded Tokens**: Use `-period=72h` for automatic expiration
2. **Orphan Tokens**: Use `-orphan` flag to prevent cascading revocation
3. **Immediate Rotation**: Revoke bootstrap tokens after migration
4. **Network Isolation**: Bootstrap only on secure management network

#### Modern Security Benefits (Workload Identity)
- **JWT-based Authentication**: No pre-shared secrets
- **Scoped Access**: Tokens issued per-task basis
- **Automatic Renewal**: Nomad handles token lifecycle
- **Audit Trail**: Better tracking of token usage

## 2. Project Structure Options

### Option A: Separate Repositories with Dispatch Triggers

**Structure:**
```
vault/
├── terraform/
├── nomad-jobs/
├── policies/
└── .github/workflows/

nomad/  
├── terraform/
├── job-templates/
├── policies/  
└── .github/workflows/
```

**Pros:**
- Clear ownership boundaries
- Independent versioning
- Granular access control
- Reduced blast radius

**Cons:**
- Coordination complexity
- Dependency management overhead
- Potential version drift

**GitOps Implementation:**
```yaml
# vault/.github/workflows/deploy.yml
name: Vault Deploy
on:
  workflow_dispatch:
  repository_dispatch:
    types: [nomad-ready]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy Vault to Nomad
        run: nomad job run vault.nomad.hcl
      
      - name: Notify Nomad of Vault Ready
        run: |
          gh api repos/org/nomad/dispatches \
            -f event_type=vault-ready
```

### Option B: Vault as Submodule of Nomad

**Structure:**
```
nomad/
├── terraform/
├── job-templates/
├── vault/ (submodule)
│   ├── terraform/
│   ├── policies/
│   └── nomad-jobs/
└── .github/workflows/
```

**Pros:**
- Nomad controls Vault lifecycle
- Single deployment pipeline
- Consistent versioning

**Cons:**
- Vault team dependency on Nomad team
- Larger repository size
- Complex submodule management

### Option C: Monorepo Approach

**Structure:**
```
infrastructure/
├── nomad/
│   ├── terraform/
│   └── jobs/
├── vault/
│   ├── terraform/  
│   └── policies/
├── shared/
│   ├── modules/
│   └── policies/
└── .github/workflows/
```

**Pros:**
- Single source of truth
- Shared modules and policies
- Atomic changes across systems
- Simplified CI/CD

**Cons:**
- Access control complexity
- Scaling challenges
- Build performance impact

**Recommended for:** Small teams, tightly coupled systems

### Option D: GitOps Config Repository Pattern

**Structure:**
```
infrastructure-config/
├── environments/
│   ├── dev/
│   │   ├── nomad/
│   │   └── vault/
│   ├── staging/
│   └── prod/
├── base/
│   ├── nomad/
│   └── vault/
└── .github/workflows/
```

**Pros:**
- Environment-first organization
- Clear promotion paths
- Configuration as code
- ArgoCD/Flux compatibility

## 3. Complete Environment Separation Strategies

### Physical Infrastructure Separation

#### Dedicated Clusters per Environment
```hcl
# dev-nomad-cluster
resource "aws_instance" "nomad_dev" {
  count         = 3
  instance_type = "t3.medium"
  
  tags = {
    Environment = "dev"
    Service     = "nomad"
  }
}

# staging-nomad-cluster  
resource "aws_instance" "nomad_staging" {
  count         = 3
  instance_type = "t3.large"
  
  tags = {
    Environment = "staging" 
    Service     = "nomad"
  }
}

# prod-nomad-cluster
resource "aws_instance" "nomad_prod" {
  count         = 5
  instance_type = "t3.xlarge"
  
  tags = {
    Environment = "prod"
    Service     = "nomad"
  }
}
```

### Network Isolation Architecture

#### VPC-Level Separation
```hcl
# Separate VPC per environment
resource "aws_vpc" "vault_nomad" {
  for_each = toset(["dev", "staging", "prod"])
  
  cidr_block           = var.vpc_cidrs[each.key]
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Name        = "${each.key}-vault-nomad"
    Environment = each.key
  }
}

# Private subnets for Nomad/Vault
resource "aws_subnet" "private" {
  for_each = local.environment_azs
  
  vpc_id            = aws_vpc.vault_nomad[each.value.env].id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az
  
  tags = {
    Name = "${each.value.env}-private-${each.value.az}"
    Tier = "private"
  }
}
```

#### Security Group Isolation
```hcl
# Nomad cluster security group
resource "aws_security_group" "nomad" {
  for_each = toset(var.environments)
  
  name_prefix = "${each.key}-nomad-"
  vpc_id      = aws_vpc.vault_nomad[each.key].id
  
  # Only allow inbound from Vault SG in same environment
  ingress {
    from_port       = 4646
    to_port         = 4648  
    protocol        = "tcp"
    security_groups = [aws_security_group.vault[each.key].id]
  }
}

# Vault cluster security group
resource "aws_security_group" "vault" {
  for_each = toset(var.environments)
  
  name_prefix = "${each.key}-vault-"
  vpc_id      = aws_vpc.vault_nomad[each.key].id
  
  # Only allow inbound from Nomad SG in same environment
  ingress {
    from_port       = 8200
    to_port         = 8201
    protocol        = "tcp" 
    security_groups = [aws_security_group.nomad[each.key].id]
  }
}
```

### Resource Overhead Analysis

#### Per-Environment Resource Requirements

**Development Environment:**
- Nomad: 3 nodes × t3.medium (2 vCPU, 4GB RAM) = $120/month
- Vault: 3 nodes × t3.small (2 vCPU, 2GB RAM) = $60/month
- Network: VPC, NAT Gateway = $45/month
- **Total: ~$225/month**

**Staging Environment:**
- Nomad: 3 nodes × t3.large (2 vCPU, 8GB RAM) = $240/month
- Vault: 3 nodes × t3.medium (2 vCPU, 4GB RAM) = $120/month
- Network: VPC, NAT Gateway = $45/month
- **Total: ~$405/month**

**Production Environment:**
- Nomad: 5 nodes × t3.xlarge (4 vCPU, 16GB RAM) = $800/month
- Vault: 5 nodes × t3.large (2 vCPU, 8GB RAM) = $400/month
- Network: VPC, NAT Gateway × 2 AZ = $90/month
- Load Balancers: $50/month
- **Total: ~$1,340/month**

**Combined Overhead: ~$1,970/month**

#### Cost Optimization Strategies

1. **Shared Services**: Use single Consul cluster for service discovery
2. **Instance Right-sizing**: Monitor and adjust based on actual usage
3. **Reserved Instances**: 30-40% savings for predictable workloads
4. **Spot Instances**: Use for non-critical dev/staging workloads

## 4. Token Migration Strategy

### Pre-Migration Checklist
- [ ] Backup existing Nomad ACL tokens
- [ ] Document current Vault policies  
- [ ] Test workload identity configuration
- [ ] Prepare rollback procedures

### Migration Process

#### Step 1: Enable Workload Identity
```bash
# Configure Nomad for workload identity
nomad operator api -ca-cert=nomad-ca.pem -client-cert=nomad.pem \
  -client-key=nomad-key.pem /v1/operator/scheduler/configuration \
  -method PUT -data @scheduler-config.json
```

#### Step 2: Configure Vault JWT Auth
```bash
# Enable JWT auth method
vault auth enable -path=nomad-workload jwt

# Configure JWT auth backend
vault write auth/nomad-workload/config \
  bound_issuer="https://nomad.service.consul:4646" \
  jwt_validation_pubkeys=@nomad-jwt.pem
```

#### Step 3: Create Workload-Specific Roles
```bash
# Create role for each application
vault write auth/nomad-workload/role/web-app \
  bound_audiences="nomad.io" \
  bound_subject="web-app" \
  bound_claims='{
    "nomad_namespace": "default",
    "nomad_job_id": "web-app"
  }' \
  user_claim="sub" \
  role_type="jwt" \
  policies="web-app-policy" \
  ttl=1h \
  max_ttl=24h
```

#### Step 4: Update Job Specifications
```hcl
job "web-app" {
  datacenters = ["dc1"]
  
  group "web" {
    count = 3
    
    task "app" {
      driver = "docker"
      
      vault {
        policies      = ["web-app-policy"]
        change_mode   = "restart"
        env           = true
        role          = "web-app"
      }
      
      config {
        image = "nginx:latest"
      }
    }
  }
}
```

### Rollback Strategy
```bash
# Emergency rollback to token-based auth
vault write nomad/config/access \
  address=https://nomad.service.consul:4646 \
  token=$NOMAD_BOOTSTRAP_TOKEN

# Disable workload identity temporarily  
nomad operator api -method PUT /v1/operator/scheduler/configuration \
  -data '{"modify_index":X,"scheduler_algorithm":"binpack"}'
```

## 5. Scalability and Security Considerations

### Horizontal Scaling Strategy

#### Multi-Region Architecture
```hcl
# Primary region Vault cluster
resource "vault_cluster" "primary" {
  region                = "us-east-1"
  performance_replicas  = ["us-west-2", "eu-west-1"]
  disaster_recovery     = "us-west-1"
}

# Performance replica clusters
resource "vault_cluster" "replica" {
  for_each = toset(["us-west-2", "eu-west-1"])
  
  region          = each.key
  mode           = "performance_replica"
  primary_cluster = vault_cluster.primary.cluster_id
}
```

#### Auto-scaling Nomad Clients
```hcl
resource "aws_autoscaling_group" "nomad_clients" {
  for_each = toset(var.environments)
  
  name                = "${each.key}-nomad-clients"
  vpc_zone_identifier = aws_subnet.private[each.key].*.id
  target_group_arns   = [aws_lb_target_group.nomad[each.key].arn]
  health_check_type   = "ELB"
  
  min_size         = var.client_counts[each.key].min
  max_size         = var.client_counts[each.key].max
  desired_capacity = var.client_counts[each.key].desired
  
  tag {
    key                 = "Environment"
    value               = each.key
    propagate_at_launch = true
  }
}
```

### Security Best Practices

#### Least Privilege Access
```hcl
# Environment-specific policies
resource "vault_policy" "app_policy" {
  for_each = var.applications
  
  name = "${each.key}-${var.environment}"
  
  policy = templatefile("policies/${each.key}.hcl", {
    environment = var.environment
    app_name    = each.key
  })
}
```

#### Audit Logging
```hcl
# Enable audit logging for all environments
resource "vault_audit" "file" {
  for_each = toset(var.environments)
  
  type = "file"
  
  options = {
    file_path = "/vault/logs/${each.key}-audit.log"
  }
}
```

## Recommendations

### For Complete Environment Separation:

1. **Use Option A (Separate Repos)** with dispatch triggers for mature organizations
2. **Implement Two-Phase Bootstrap** with immediate token rotation
3. **Migrate to Workload Identity** for improved security
4. **Deploy dedicated clusters** per environment with proper network isolation
5. **Implement comprehensive monitoring** and alerting across all environments

### Implementation Priority:

1. **Phase 1**: Set up basic separate environments with temporary token bootstrap
2. **Phase 2**: Implement proper network isolation and security groups  
3. **Phase 3**: Migrate to workload identity authentication
4. **Phase 4**: Add multi-region disaster recovery capabilities

This architecture provides maximum security through complete isolation while maintaining operational efficiency through automation and proper GitOps practices.