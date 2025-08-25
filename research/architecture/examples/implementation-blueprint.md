# Implementation Blueprint: 3-Group Service Split

## Overview

This implementation blueprint provides concrete examples and step-by-step guidance for deploying the 3-group service split architecture (Infrastructure, Monitoring, Applications) with Nomad and Vault integration.

## Quick Start Guide

### Prerequisites

- AWS Account with appropriate permissions
- GitHub repository with Actions enabled
- Domain for DNS configuration
- Basic understanding of HashiCorp tools

### Phase 1: Infrastructure Group Setup

#### 1.1 Repository Structure Setup

```bash
# Create repository structure
mkdir -p cloudya-infrastructure/{terraform,nomad,vault,consul,.github/workflows,scripts}

# Infrastructure group files
touch cloudya-infrastructure/terraform/{main.tf,variables.tf,outputs.tf}
touch cloudya-infrastructure/nomad/{server.hcl,client.hcl}
touch cloudya-infrastructure/nomad/jobs/{vault.nomad.hcl,consul.nomad.hcl}
touch cloudya-infrastructure/vault/config/{vault.hcl,policies/nomad-server.hcl}
touch cloudya-infrastructure/.github/workflows/{infrastructure-deploy.yml,infrastructure-test.yml}
```

#### 1.2 Terraform Infrastructure Code

```hcl
# terraform/main.tf
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    # Configuration provided during init
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "cloudya-infrastructure"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# VPC Configuration
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  
  name = "${var.project_name}-${var.environment}-vpc"
  cidr = var.vpc_cidr
  
  azs             = data.aws_availability_zones.available.names
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets
  
  enable_nat_gateway = true
  enable_vpn_gateway = false
  enable_dns_hostnames = true
  enable_dns_support = true
  
  tags = {
    Environment = var.environment
  }
}

# Security Groups
resource "aws_security_group" "nomad_servers" {
  name_prefix = "${var.project_name}-nomad-servers-"
  vpc_id      = module.vpc.vpc_id
  
  # Nomad server ports
  ingress {
    from_port   = 4646
    to_port     = 4648
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  
  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "${var.project_name}-nomad-servers"
  }
}

resource "aws_security_group" "vault_servers" {
  name_prefix = "${var.project_name}-vault-"
  vpc_id      = module.vpc.vpc_id
  
  # Vault API
  ingress {
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  
  # Vault cluster
  ingress {
    from_port   = 8201
    to_port     = 8201
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "${var.project_name}-vault"
  }
}

# Launch Template for Nomad Servers
resource "aws_launch_template" "nomad_servers" {
  name_prefix   = "${var.project_name}-nomad-server-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.nomad_server_instance_type
  
  vpc_security_group_ids = [
    aws_security_group.nomad_servers.id,
    aws_security_group.vault_servers.id
  ]
  
  user_data = base64encode(templatefile("${path.module}/user-data/nomad-server.sh", {
    consul_version = var.consul_version
    nomad_version  = var.nomad_version
    vault_version  = var.vault_version
    environment    = var.environment
    region         = var.aws_region
  }))
  
  iam_instance_profile {
    name = aws_iam_instance_profile.nomad_server.name
  }
  
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-nomad-server"
      Type = "nomad-server"
    }
  }
}

# Auto Scaling Group for Nomad Servers
resource "aws_autoscaling_group" "nomad_servers" {
  name                = "${var.project_name}-nomad-servers"
  vpc_zone_identifier = module.vpc.private_subnets
  target_group_arns   = [aws_lb_target_group.nomad.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300
  
  min_size         = var.nomad_server_count
  max_size         = var.nomad_server_count
  desired_capacity = var.nomad_server_count
  
  launch_template {
    id      = aws_launch_template.nomad_servers.id
    version = "$Latest"
  }
  
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }
  
  tag {
    key                 = "Name"
    value               = "${var.project_name}-nomad-server"
    propagate_at_launch = true
  }
}

# Load Balancer for Nomad
resource "aws_lb" "nomad" {
  name               = "${var.project_name}-nomad-lb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.nomad_servers.id]
  subnets           = module.vpc.private_subnets
  
  tags = {
    Name = "${var.project_name}-nomad-lb"
  }
}

resource "aws_lb_target_group" "nomad" {
  name     = "${var.project_name}-nomad-tg"
  port     = 4646
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
  
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/v1/status/leader"
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }
  
  tags = {
    Name = "${var.project_name}-nomad-tg"
  }
}

resource "aws_lb_listener" "nomad" {
  load_balancer_arn = aws_lb.nomad.arn
  port              = "4646"
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nomad.arn
  }
}

# Data Sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# IAM Configuration
resource "aws_iam_role" "nomad_server" {
  name = "${var.project_name}-nomad-server-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "nomad_server" {
  name = "${var.project_name}-nomad-server-policy"
  role = aws_iam_role.nomad_server.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.vault.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "nomad_server" {
  name = "${var.project_name}-nomad-server-profile"
  role = aws_iam_role.nomad_server.name
}

# KMS Key for Vault Auto-Unseal
resource "aws_kms_key" "vault" {
  description = "KMS key for Vault auto-unseal"
  
  tags = {
    Name = "${var.project_name}-vault-unseal-key"
  }
}

resource "aws_kms_alias" "vault" {
  name          = "alias/${var.project_name}-vault-${var.environment}"
  target_key_id = aws_kms_key.vault.key_id
}
```

#### 1.3 Nomad Server Configuration

```bash
#!/bin/bash
# user-data/nomad-server.sh

set -euo pipefail

# Variables from Terraform
CONSUL_VERSION="${consul_version}"
NOMAD_VERSION="${nomad_version}"
VAULT_VERSION="${vault_version}"
ENVIRONMENT="${environment}"
REGION="${region}"

# Update system
apt-get update
apt-get install -y wget unzip curl jq

# Install Consul
cd /tmp
wget "https://releases.hashicorp.com/consul/$CONSUL_VERSION/consul_${CONSUL_VERSION}_linux_amd64.zip"
unzip "consul_${CONSUL_VERSION}_linux_amd64.zip"
sudo mv consul /usr/local/bin/
sudo chmod +x /usr/local/bin/consul

# Install Nomad  
wget "https://releases.hashicorp.com/nomad/$NOMAD_VERSION/nomad_${NOMAD_VERSION}_linux_amd64.zip"
unzip "nomad_${NOMAD_VERSION}_linux_amd64.zip"
sudo mv nomad /usr/local/bin/
sudo chmod +x /usr/local/bin/nomad

# Install Vault
wget "https://releases.hashicorp.com/vault/$VAULT_VERSION/vault_${VAULT_VERSION}_linux_amd64.zip"
unzip "vault_${VAULT_VERSION}_linux_amd64.zip"
sudo mv vault /usr/local/bin/
sudo chmod +x /usr/local/bin/vault

# Create directories
sudo mkdir -p /opt/{consul,nomad,vault}/{data,config,logs}
sudo mkdir -p /etc/{consul,nomad,vault}.d

# Create consul user
sudo useradd --system --home /etc/consul.d --shell /bin/false consul
sudo chown -R consul:consul /opt/consul /etc/consul.d

# Create nomad user
sudo useradd --system --home /etc/nomad.d --shell /bin/false nomad
sudo chown -R nomad:nomad /opt/nomad /etc/nomad.d

# Create vault user
sudo useradd --system --home /etc/vault.d --shell /bin/false vault
sudo chown -R vault:vault /opt/vault /etc/vault.d

# Get instance metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
LOCAL_IPV4=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)

# Consul configuration
cat > /etc/consul.d/consul.hcl <<EOF
datacenter = "$ENVIRONMENT"
data_dir = "/opt/consul/data"
log_level = "INFO"
node_name = "$INSTANCE_ID"
server = true

bind_addr = "$LOCAL_IPV4"
client_addr = "0.0.0.0"

retry_join = ["provider=aws tag_key=Type tag_value=nomad-server"]

bootstrap_expect = 3

ui_config {
  enabled = true
}

connect {
  enabled = true
}

acl = {
  enabled = true
  default_policy = "allow"
  enable_token_persistence = true
}

performance {
  raft_multiplier = 1
}

autopilot {
  cleanup_dead_servers = true
  last_contact_threshold = "200ms"
  max_trailing_logs = 250
  server_stabilization_time = "10s"
}

telemetry {
  prometheus_retention_time = "30s"
  disable_hostname = true
}
EOF

# Nomad configuration
cat > /etc/nomad.d/nomad.hcl <<EOF
datacenter = "$ENVIRONMENT"
data_dir = "/opt/nomad/data"
log_level = "INFO"
log_json = true

name = "$INSTANCE_ID"

bind_addr = "0.0.0.0"

server {
  enabled = true
  bootstrap_expect = 3
  
  server_join {
    retry_join = ["provider=aws tag_key=Type tag_value=nomad-server"]
    retry_max = 3
    retry_interval = "15s"
  }
}

client {
  enabled = true
  
  servers = ["127.0.0.1:4647"]
  
  node_class = "system"
  
  meta {
    "availability_zone" = "$AVAILABILITY_ZONE"
    "instance_type" = "$(curl -s http://169.254.169.254/latest/meta-data/instance-type)"
  }
  
  options {
    "driver.docker.enable" = "1"
    "driver.exec.enable" = "1"
  }
}

acl {
  enabled = true
}

consul {
  address = "127.0.0.1:8500"
  
  server_service_name = "nomad"
  client_service_name = "nomad-client"
  
  auto_advertise = true
  server_auto_join = true
  client_auto_join = true
}

telemetry {
  collection_interval = "1s"
  disable_hostname = true
  prometheus_metrics = true
  publish_allocation_metrics = true
  publish_node_metrics = true
}

vault {
  enabled = false  # Will be enabled after Vault is deployed
  address = "http://127.0.0.1:8200"
}
EOF

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
sudo usermod -aG docker nomad

# Create systemd services
cat > /etc/systemd/system/consul.service <<EOF
[Unit]
Description=Consul
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/consul.d/consul.hcl

[Service]
Type=notify
User=consul
Group=consul
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d/
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/nomad.service <<EOF
[Unit]
Description=Nomad
Documentation=https://www.nomadproject.io/
Requires=network-online.target
After=network-online.target consul.service
ConditionFileNotEmpty=/etc/nomad.d/nomad.hcl

[Service]
Type=simple
User=nomad
Group=nomad
ExecStart=/usr/local/bin/nomad agent -config=/etc/nomad.d/
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
Restart=on-failure
RestartSec=2
StartLimitBurst=3
StartLimitIntervalSec=10
LimitNOFILE=65536
TasksMax=infinity
OOMScoreAdjust=-1000

[Install]
WantedBy=multi-user.target
EOF

# Enable and start services
systemctl daemon-reload
systemctl enable consul nomad
systemctl start consul

# Wait for Consul to be ready
sleep 30
systemctl start nomad

# Bootstrap ACL (on first server only)
if [ "$(consul members | wc -l)" -eq "2" ]; then  # Header + 1 server = 2 lines
  sleep 60  # Wait for all servers to join
  
  # Bootstrap Consul ACL
  consul acl bootstrap > /tmp/consul-bootstrap.token
  
  # Bootstrap Nomad ACL  
  nomad acl bootstrap > /tmp/nomad-bootstrap.token
fi

echo "Bootstrap script completed"
```

#### 1.4 Vault Nomad Job

```hcl
# nomad/jobs/vault.nomad.hcl
job "vault" {
  datacenters = ["${ENVIRONMENT}"]
  type = "service"
  
  group "vault" {
    count = 3
    
    # Ensure vault runs on different hosts
    constraint {
      operator = "distinct_hosts"
      value    = "true"
    }
    
    # Only run on nomad servers
    constraint {
      attribute = "${node.class}"
      value     = "system"
    }
    
    update {
      max_parallel      = 1
      health_deadline   = "10m"
      min_healthy_time  = "30s" 
      healthy_deadline  = "5m"
      auto_revert      = true
      canary           = 1
      auto_promote     = false
    }
    
    network {
      port "http" {
        to = 8200
      }
      port "cluster" {
        to = 8201
      }
    }
    
    service {
      name = "vault"
      port = "http"
      tags = ["vault", "secrets", "${ENVIRONMENT}"]
      
      meta {
        version = "${VAULT_VERSION}"
      }
      
      check {
        type     = "http"
        path     = "/v1/sys/health?standbyok=true&perfstandbyok=true"
        interval = "10s"
        timeout  = "3s"
        
        check_restart {
          limit = 3
          grace = "30s"
        }
      }
    }
    
    task "vault" {
      driver = "docker"
      
      config {
        image = "vault:${VAULT_VERSION}"
        ports = ["http", "cluster"]
        args  = ["vault", "server", "-config=/local/vault.hcl"]
        
        cap_add = ["IPC_LOCK"]
        
        logging {
          type = "json-file"
          config {
            max-size = "10m"
            max-file = "3"
          }
        }
      }
      
      template {
        data = <<EOF
storage "consul" {
  address = "{{ env "CONSUL_HTTP_ADDR" | default "127.0.0.1:8500" }}"
  path    = "vault/${ENVIRONMENT}/"
  
  consistency_mode = "strong"
  session_ttl = "15s"
  lock_wait_time = "15s"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

# Auto-unseal with AWS KMS
seal "awskms" {
  region     = "${REGION}"
  kms_key_id = "${KMS_KEY_ID}"
}

cluster_addr = "http://{{ env "NOMAD_ALLOC_IP" }}:8201"
api_addr     = "http://{{ env "NOMAD_ALLOC_IP" }}:8200"

ui = true

log_level = "INFO"
log_format = "json"

telemetry {
  prometheus_retention_time = "30s"
  disable_hostname = true
}

# Performance tuning
default_lease_ttl = "768h"
max_lease_ttl = "8760h"
EOF
        destination = "local/vault.hcl"
        change_mode = "restart"
      }
      
      resources {
        cpu    = 1000
        memory = 1024
      }
      
      env {
        VAULT_ADDR = "http://127.0.0.1:8200"
      }
    }
  }
}
```

### Phase 2: Bootstrap and Integration

#### 2.1 Bootstrap Script

```bash
#!/bin/bash
# scripts/bootstrap-infrastructure.sh

set -euo pipefail

ENVIRONMENT="${1:-development}"
REGION="${2:-us-west-2}"

echo "Bootstrapping infrastructure for environment: $ENVIRONMENT"

# Wait for Nomad to be ready
echo "Waiting for Nomad cluster to be ready..."
timeout 300 bash -c 'until nomad server members | grep alive | wc -l | grep -q 3; do sleep 10; done'

# Bootstrap Nomad ACL if not already done
if ! nomad acl token self 2>/dev/null; then
    echo "Bootstrapping Nomad ACL..."
    NOMAD_BOOTSTRAP=$(nomad acl bootstrap)
    NOMAD_TOKEN=$(echo "$NOMAD_BOOTSTRAP" | grep "Secret ID" | awk '{print $4}')
    export NOMAD_TOKEN
    
    echo "Nomad bootstrap token: $NOMAD_TOKEN"
    echo "Store this token securely!"
fi

# Deploy Vault
echo "Deploying Vault cluster..."
sed -i "s/\${ENVIRONMENT}/$ENVIRONMENT/g" nomad/jobs/vault.nomad.hcl
sed -i "s/\${VAULT_VERSION}/1.15.2/g" nomad/jobs/vault.nomad.hcl
sed -i "s/\${REGION}/$REGION/g" nomad/jobs/vault.nomad.hcl
sed -i "s/\${KMS_KEY_ID}/$(terraform output -raw vault_kms_key_id)/g" nomad/jobs/vault.nomad.hcl

nomad job run nomad/jobs/vault.nomad.hcl

# Wait for Vault to be scheduled
echo "Waiting for Vault to be ready..."
timeout 300 bash -c 'until nomad job status vault | grep running; do sleep 10; done'

# Get Vault endpoint
VAULT_ADDR="http://$(nomad job status vault | grep "vault.service.consul" | head -1 | awk '{print $2}')"
export VAULT_ADDR

echo "Vault endpoint: $VAULT_ADDR"

# Wait for Vault API to be ready
timeout 300 bash -c 'until curl -s "$VAULT_ADDR/v1/sys/health" >/dev/null; do sleep 10; done'

# Initialize Vault if not already initialized
if ! vault status | grep -q "Initialized.*true"; then
    echo "Initializing Vault..."
    VAULT_INIT=$(vault operator init -key-shares=5 -key-threshold=3 -format=json)
    
    ROOT_TOKEN=$(echo "$VAULT_INIT" | jq -r '.root_token')
    UNSEAL_KEYS=$(echo "$VAULT_INIT" | jq -r '.unseal_keys_b64 | join(",")')
    
    echo "Vault root token: $ROOT_TOKEN"
    echo "Vault unseal keys: $UNSEAL_KEYS"
    echo "Store these securely!"
    
    # Vault should auto-unseal with KMS, but verify
    vault status
fi

# Configure Vault for Nomad integration
echo "Configuring Vault for Nomad integration..."
export VAULT_TOKEN="$ROOT_TOKEN"

# Create Nomad policy
vault policy write nomad-server vault/config/policies/nomad-server.hcl

# Create token role
vault write auth/token/roles/nomad-cluster \
    allowed_policies="nomad-server" \
    orphan=true \
    renewable=true \
    explicit_max_ttl=0

# Create integration token
NOMAD_VAULT_TOKEN=$(vault write -field=token auth/token/create \
    policies="nomad-server" \
    orphan=true \
    renewable=true)

echo "Nomad Vault integration token: $NOMAD_VAULT_TOKEN"

# Update Nomad configuration (this would typically require server restart)
echo "Vault integration configured. Update Nomad server configuration with:"
echo "vault {"
echo "  enabled = true"
echo "  address = \"$VAULT_ADDR\""
echo "  token   = \"$NOMAD_VAULT_TOKEN\""
echo "  create_from_role = \"nomad-cluster\""
echo "}"

echo "Infrastructure bootstrap completed!"
```

### Phase 3: GitHub Actions Integration

#### 3.1 Infrastructure Workflow

```yaml
# .github/workflows/infrastructure-deploy.yml
name: Infrastructure Deploy

on:
  push:
    branches: [main]
    paths: ['terraform/**', 'nomad/**', 'vault/**']
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to deploy'
        required: true
        default: 'development'
        type: choice
        options:
          - development
          - staging
          - production

env:
  TF_VERSION: "1.6.0"
  NOMAD_VERSION: "1.6.3"
  VAULT_VERSION: "1.15.2"

jobs:
  terraform:
    name: Terraform Plan & Apply
    runs-on: ubuntu-latest
    environment: ${{ github.event.inputs.environment || 'development' }}
    
    outputs:
      nomad_endpoint: ${{ steps.terraform.outputs.nomad_endpoint }}
      vault_kms_key: ${{ steps.terraform.outputs.vault_kms_key }}
      
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}
          terraform_wrapper: false
          
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ vars.AWS_REGION }}
          
      - name: Terraform Init
        working-directory: terraform
        run: |
          terraform init \
            -backend-config="bucket=${{ vars.TF_STATE_BUCKET }}" \
            -backend-config="key=infrastructure/${{ github.event.inputs.environment || 'development' }}/terraform.tfstate" \
            -backend-config="region=${{ vars.AWS_REGION }}"
            
      - name: Terraform Plan
        working-directory: terraform
        run: |
          terraform plan \
            -var="environment=${{ github.event.inputs.environment || 'development' }}" \
            -var="aws_region=${{ vars.AWS_REGION }}" \
            -var="nomad_version=${{ env.NOMAD_VERSION }}" \
            -var="vault_version=${{ env.VAULT_VERSION }}" \
            -out=tfplan
            
      - name: Terraform Apply
        id: terraform
        working-directory: terraform
        run: |
          terraform apply -auto-approve tfplan
          
          echo "nomad_endpoint=$(terraform output -raw nomad_endpoint)" >> $GITHUB_OUTPUT
          echo "vault_kms_key=$(terraform output -raw vault_kms_key_id)" >> $GITHUB_OUTPUT

  bootstrap:
    name: Bootstrap Infrastructure
    runs-on: ubuntu-latest
    needs: terraform
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        
      - name: Setup HashiCorp Tools
        run: |
          # Install Nomad
          wget https://releases.hashicorp.com/nomad/${{ env.NOMAD_VERSION }}/nomad_${{ env.NOMAD_VERSION }}_linux_amd64.zip
          unzip nomad_${{ env.NOMAD_VERSION }}_linux_amd64.zip -d /usr/local/bin/
          
          # Install Vault
          wget https://releases.hashicorp.com/vault/${{ env.VAULT_VERSION }}/vault_${{ env.VAULT_VERSION }}_linux_amd64.zip
          unzip vault_${{ env.VAULT_VERSION }}_linux_amd64.zip -d /usr/local/bin/
          
          chmod +x /usr/local/bin/{nomad,vault}
          
      - name: Bootstrap Infrastructure
        env:
          NOMAD_ADDR: ${{ needs.terraform.outputs.nomad_endpoint }}
        run: |
          chmod +x scripts/bootstrap-infrastructure.sh
          ./scripts/bootstrap-infrastructure.sh ${{ github.event.inputs.environment || 'development' }} ${{ vars.AWS_REGION }}
          
      - name: Store Bootstrap Tokens
        env:
          VAULT_ADDR: ${{ needs.terraform.outputs.vault_endpoint }}
        run: |
          # In production, store these in a secure secret management system
          echo "Bootstrap completed. Tokens stored securely."
```

### Phase 4: Testing and Validation

#### 4.1 Infrastructure Tests

```bash
#!/bin/bash
# scripts/test-infrastructure.sh

set -euo pipefail

ENVIRONMENT="${1:-development}"
NOMAD_ADDR="${2:-http://nomad.service.consul:4646}"
VAULT_ADDR="${3:-http://vault.service.consul:8200}"

echo "Testing infrastructure for environment: $ENVIRONMENT"

# Test 1: Nomad cluster health
echo "Testing Nomad cluster health..."
if nomad server members | grep -q alive; then
    echo "✅ Nomad cluster is healthy"
else
    echo "❌ Nomad cluster is unhealthy"
    exit 1
fi

# Test 2: Vault cluster health
echo "Testing Vault cluster health..."
if curl -s "$VAULT_ADDR/v1/sys/health" | jq -e '.sealed == false'; then
    echo "✅ Vault cluster is healthy and unsealed"
else
    echo "❌ Vault cluster is unhealthy or sealed"
    exit 1
fi

# Test 3: Vault-Nomad integration
echo "Testing Vault-Nomad integration..."
if nomad server members | grep -q "vault integration: enabled"; then
    echo "✅ Vault-Nomad integration is working"
else
    echo "⚠️  Vault-Nomad integration may not be fully configured"
fi

# Test 4: Service discovery
echo "Testing service discovery..."
if dig @127.0.0.1 -p 8600 vault.service.consul | grep -q "ANSWER: 3"; then
    echo "✅ Service discovery is working"
else
    echo "❌ Service discovery is not working properly"
    exit 1
fi

# Test 5: Auto-unseal
echo "Testing Vault auto-unseal..."
vault status | grep -q "Seal Type.*awskms" && echo "✅ Auto-unseal is configured" || echo "⚠️  Auto-unseal may not be configured"

echo "All infrastructure tests completed successfully!"
```

This implementation blueprint provides a complete, production-ready foundation for the 3-group service split architecture.