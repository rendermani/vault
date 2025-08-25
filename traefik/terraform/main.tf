# Main Terraform Configuration - Production-Ready IaC
# This is the root module that orchestrates all infrastructure components

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.20"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    nomad = {
      source  = "hashicorp/nomad"
      version = "~> 2.0"
    }
    consul = {
      source  = "hashicorp/consul"
      version = "~> 2.20"
    }
  }

  backend "s3" {
    bucket         = var.terraform_state_bucket
    key            = "infrastructure/terraform.tfstate"
    region         = var.aws_region
    encrypt        = true
    dynamodb_table = var.terraform_lock_table
    
    # Workspace-based state isolation
    workspace_key_prefix = "workspaces"
  }
}

# Local variables for common tags and naming
locals {
  common_tags = merge(var.additional_tags, {
    Environment   = var.environment
    Project       = var.project_name
    ManagedBy     = "terraform"
    Owner         = var.owner
    CostCenter    = var.cost_center
    Compliance    = var.compliance_level
    Backup        = var.backup_required
    CreatedAt     = formatdate("YYYY-MM-DD", timestamp())
  })
  
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Resource naming convention
  naming_convention = {
    vpc               = "${local.name_prefix}-vpc"
    vault_cluster     = "${local.name_prefix}-vault"
    nomad_cluster     = "${local.name_prefix}-nomad"
    consul_cluster    = "${local.name_prefix}-consul"
    monitoring_stack  = "${local.name_prefix}-monitoring"
    security_group    = "${local.name_prefix}-sg"
    load_balancer     = "${local.name_prefix}-lb"
  }
}

# Data sources for existing resources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# Networking Module - Foundation layer
module "networking" {
  source = "./modules/networking"
  
  name_prefix         = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  availability_zones = data.aws_availability_zones.available.names
  
  # Subnet configuration
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
  
  # Network security
  enable_nat_gateway     = var.enable_nat_gateway
  enable_vpn_gateway     = var.enable_vpn_gateway
  enable_dns_hostnames   = true
  enable_dns_support     = true
  enable_flow_logs       = var.enable_vpc_flow_logs
  
  tags = local.common_tags
}

# Security Module - Security foundation
module "security" {
  source = "./modules/security"
  
  name_prefix = local.name_prefix
  vpc_id      = module.networking.vpc_id
  
  # Security groups configuration
  security_groups = var.security_groups
  
  # WAF configuration
  enable_waf = var.enable_waf
  waf_rules  = var.waf_rules
  
  # Certificate management
  domain_names = var.domain_names
  
  # Secrets management
  enable_secrets_manager = true
  
  tags = local.common_tags
  
  depends_on = [module.networking]
}

# Vault Cluster Module - Secrets management
module "vault" {
  source = "./modules/vault"
  
  name_prefix = local.name_prefix
  
  # Networking
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  
  # Security
  security_group_ids = [module.security.vault_security_group_id]
  
  # Cluster configuration
  vault_version     = var.vault_version
  vault_nodes       = var.vault_nodes
  instance_type     = var.vault_instance_type
  
  # Storage
  vault_storage_type   = var.vault_storage_type
  vault_storage_size   = var.vault_storage_size
  enable_auto_unseal   = var.vault_enable_auto_unseal
  
  # High availability
  enable_auto_scaling = var.vault_enable_auto_scaling
  min_capacity       = var.vault_min_capacity
  max_capacity       = var.vault_max_capacity
  
  # Backup configuration
  enable_snapshots    = var.vault_enable_snapshots
  snapshot_schedule   = var.vault_snapshot_schedule
  snapshot_retention  = var.vault_snapshot_retention
  
  # Monitoring
  enable_cloudwatch = var.enable_cloudwatch_monitoring
  enable_datadog    = var.enable_datadog_monitoring
  
  tags = local.common_tags
  
  depends_on = [module.networking, module.security]
}

# Compute Module - Application infrastructure
module "compute" {
  source = "./modules/compute"
  
  name_prefix = local.name_prefix
  
  # Networking
  vpc_id              = module.networking.vpc_id
  private_subnet_ids  = module.networking.private_subnet_ids
  public_subnet_ids   = module.networking.public_subnet_ids
  
  # Security
  security_group_ids = [
    module.security.app_security_group_id,
    module.security.lb_security_group_id
  ]
  
  # Load balancer configuration
  enable_application_lb = var.enable_application_lb
  enable_network_lb     = var.enable_network_lb
  ssl_certificate_arn   = module.security.ssl_certificate_arn
  
  # Auto scaling configuration
  enable_auto_scaling     = var.enable_auto_scaling
  min_capacity           = var.min_capacity
  max_capacity           = var.max_capacity
  desired_capacity       = var.desired_capacity
  
  # Container orchestration
  enable_ecs_cluster     = var.enable_ecs_cluster
  enable_eks_cluster     = var.enable_eks_cluster
  enable_nomad_cluster   = var.enable_nomad_cluster
  
  # Nomad configuration (existing Traefik integration)
  nomad_version     = var.nomad_version
  nomad_datacenter  = var.nomad_datacenter
  consul_integration = true
  
  tags = local.common_tags
  
  depends_on = [module.networking, module.security, module.vault]
}

# Monitoring Module - Observability stack
module "monitoring" {
  source = "./modules/monitoring"
  
  name_prefix = local.name_prefix
  
  # Networking
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  
  # Security
  security_group_ids = [module.security.monitoring_security_group_id]
  
  # Prometheus configuration
  enable_prometheus = var.enable_prometheus
  prometheus_retention = var.prometheus_retention
  
  # Grafana configuration
  enable_grafana = var.enable_grafana
  grafana_admin_password = var.grafana_admin_password
  
  # Alerting
  enable_alertmanager = var.enable_alertmanager
  alert_rules         = var.alert_rules
  notification_channels = var.notification_channels
  
  # Log aggregation
  enable_elasticsearch = var.enable_elasticsearch
  enable_fluentd      = var.enable_fluentd
  log_retention_days  = var.log_retention_days
  
  # Metrics collection
  enable_node_exporter    = true
  enable_vault_exporter   = true
  enable_traefik_exporter = true
  enable_nomad_exporter   = true
  
  tags = local.common_tags
  
  depends_on = [module.compute]
}

# Storage Module - Persistent data storage
module "storage" {
  source = "./modules/storage"
  
  name_prefix = local.name_prefix
  
  # Database configuration
  enable_rds = var.enable_rds
  db_config  = var.db_config
  
  # Object storage
  enable_s3_buckets = var.enable_s3_buckets
  s3_bucket_configs = var.s3_bucket_configs
  
  # Backup storage
  backup_retention_days = var.backup_retention_days
  enable_cross_region_backup = var.enable_cross_region_backup
  
  # Encryption
  enable_encryption_at_rest = var.enable_encryption_at_rest
  kms_key_id               = var.kms_key_id
  
  tags = local.common_tags
  
  depends_on = [module.networking, module.security]
}

# Automation Module - Self-healing and automation
module "automation" {
  source = "./modules/automation"
  
  name_prefix = local.name_prefix
  
  # Lambda functions for automation
  enable_auto_healing    = var.enable_auto_healing
  enable_cost_optimization = var.enable_cost_optimization
  enable_compliance_check = var.enable_compliance_check
  
  # EventBridge rules
  automation_schedules = var.automation_schedules
  
  # SNS topics for notifications
  notification_topics = var.notification_topics
  
  # IAM roles for automation
  automation_role_policies = var.automation_role_policies
  
  tags = local.common_tags
  
  depends_on = [module.compute, module.monitoring]
}