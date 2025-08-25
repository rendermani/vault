# Variables Definition - Comprehensive Infrastructure Configuration

# Core Infrastructure Variables
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "cloudya-traefik"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "owner" {
  description = "Resource owner"
  type        = string
  default     = "devops-team"
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = "engineering"
}

variable "compliance_level" {
  description = "Compliance level (basic, enhanced, strict)"
  type        = string
  default     = "enhanced"
  
  validation {
    condition     = contains(["basic", "enhanced", "strict"], var.compliance_level)
    error_message = "Compliance level must be basic, enhanced, or strict."
  }
}

variable "backup_required" {
  description = "Whether backup is required"
  type        = string
  default     = "yes"
}

variable "additional_tags" {
  description = "Additional resource tags"
  type        = map(string)
  default     = {}
}

# State Management Variables
variable "terraform_state_bucket" {
  description = "S3 bucket for Terraform state"
  type        = string
}

variable "terraform_lock_table" {
  description = "DynamoDB table for Terraform state locking"
  type        = string
}

# Networking Variables
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid CIDR block."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  
  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "At least 2 public subnets are required for high availability."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
  
  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least 2 private subnets are required for high availability."
  }
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for database subnets"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24", "10.0.22.0/24"]
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "enable_vpn_gateway" {
  description = "Enable VPN Gateway"
  type        = bool
  default     = false
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = true
}

# Security Variables
variable "security_groups" {
  description = "Security group configurations"
  type = map(object({
    description = string
    ingress_rules = list(object({
      from_port   = number
      to_port     = number
      protocol    = string
      cidr_blocks = list(string)
      description = string
    }))
    egress_rules = list(object({
      from_port   = number
      to_port     = number
      protocol    = string
      cidr_blocks = list(string)
      description = string
    }))
  }))
  default = {
    web = {
      description = "Web server security group"
      ingress_rules = [
        {
          from_port   = 80
          to_port     = 80
          protocol    = "tcp"
          cidr_blocks = ["0.0.0.0/0"]
          description = "HTTP traffic"
        },
        {
          from_port   = 443
          to_port     = 443
          protocol    = "tcp"
          cidr_blocks = ["0.0.0.0/0"]
          description = "HTTPS traffic"
        }
      ]
      egress_rules = [
        {
          from_port   = 0
          to_port     = 0
          protocol    = "-1"
          cidr_blocks = ["0.0.0.0/0"]
          description = "All outbound traffic"
        }
      ]
    }
  }
}

variable "enable_waf" {
  description = "Enable AWS WAF"
  type        = bool
  default     = true
}

variable "waf_rules" {
  description = "WAF rules configuration"
  type        = list(string)
  default     = ["AWSManagedRulesCommonRuleSet", "AWSManagedRulesKnownBadInputsRuleSet"]
}

variable "domain_names" {
  description = "Domain names for SSL certificates"
  type        = list(string)
  default     = []
}

# Vault Variables
variable "vault_version" {
  description = "HashiCorp Vault version"
  type        = string
  default     = "1.15.2"
}

variable "vault_nodes" {
  description = "Number of Vault nodes"
  type        = number
  default     = 3
  
  validation {
    condition     = var.vault_nodes >= 3 && var.vault_nodes % 2 == 1
    error_message = "Vault nodes must be an odd number >= 3 for HA."
  }
}

variable "vault_instance_type" {
  description = "Instance type for Vault nodes"
  type        = string
  default     = "t3.medium"
}

variable "vault_storage_type" {
  description = "Storage backend for Vault (consul, dynamodb, s3)"
  type        = string
  default     = "consul"
  
  validation {
    condition     = contains(["consul", "dynamodb", "s3"], var.vault_storage_type)
    error_message = "Vault storage type must be consul, dynamodb, or s3."
  }
}

variable "vault_storage_size" {
  description = "Storage size for Vault in GB"
  type        = number
  default     = 100
}

variable "vault_enable_auto_unseal" {
  description = "Enable auto unseal for Vault"
  type        = bool
  default     = true
}

variable "vault_enable_auto_scaling" {
  description = "Enable auto scaling for Vault"
  type        = bool
  default     = true
}

variable "vault_min_capacity" {
  description = "Minimum capacity for Vault auto scaling"
  type        = number
  default     = 3
}

variable "vault_max_capacity" {
  description = "Maximum capacity for Vault auto scaling"
  type        = number
  default     = 9
}

variable "vault_enable_snapshots" {
  description = "Enable automated snapshots for Vault"
  type        = bool
  default     = true
}

variable "vault_snapshot_schedule" {
  description = "Snapshot schedule (cron expression)"
  type        = string
  default     = "0 2 * * *"  # Daily at 2 AM
}

variable "vault_snapshot_retention" {
  description = "Snapshot retention in days"
  type        = number
  default     = 30
}

# Compute Variables
variable "enable_application_lb" {
  description = "Enable Application Load Balancer"
  type        = bool
  default     = true
}

variable "enable_network_lb" {
  description = "Enable Network Load Balancer"
  type        = bool
  default     = false
}

variable "enable_auto_scaling" {
  description = "Enable auto scaling"
  type        = bool
  default     = true
}

variable "min_capacity" {
  description = "Minimum capacity for auto scaling"
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum capacity for auto scaling"
  type        = number
  default     = 10
}

variable "desired_capacity" {
  description = "Desired capacity for auto scaling"
  type        = number
  default     = 3
}

variable "enable_ecs_cluster" {
  description = "Enable ECS cluster"
  type        = bool
  default     = false
}

variable "enable_eks_cluster" {
  description = "Enable EKS cluster"
  type        = bool
  default     = false
}

variable "enable_nomad_cluster" {
  description = "Enable Nomad cluster (existing Traefik integration)"
  type        = bool
  default     = true
}

variable "nomad_version" {
  description = "HashiCorp Nomad version"
  type        = string
  default     = "1.6.2"
}

variable "nomad_datacenter" {
  description = "Nomad datacenter name"
  type        = string
  default     = "dc1"
}

# Monitoring Variables
variable "enable_cloudwatch_monitoring" {
  description = "Enable CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "enable_datadog_monitoring" {
  description = "Enable Datadog monitoring"
  type        = bool
  default     = false
}

variable "enable_prometheus" {
  description = "Enable Prometheus"
  type        = bool
  default     = true
}

variable "prometheus_retention" {
  description = "Prometheus data retention in days"
  type        = number
  default     = 30
}

variable "enable_grafana" {
  description = "Enable Grafana"
  type        = bool
  default     = true
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
  default     = null
}

variable "enable_alertmanager" {
  description = "Enable AlertManager"
  type        = bool
  default     = true
}

variable "alert_rules" {
  description = "Alert rules configuration"
  type        = list(string)
  default     = []
}

variable "notification_channels" {
  description = "Notification channels for alerts"
  type        = map(string)
  default     = {}
}

variable "enable_elasticsearch" {
  description = "Enable Elasticsearch"
  type        = bool
  default     = false
}

variable "enable_fluentd" {
  description = "Enable Fluentd"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Log retention in days"
  type        = number
  default     = 90
}

# Storage Variables
variable "enable_rds" {
  description = "Enable RDS database"
  type        = bool
  default     = false
}

variable "db_config" {
  description = "Database configuration"
  type = object({
    engine         = string
    engine_version = string
    instance_class = string
    allocated_storage = number
    multi_az      = bool
    backup_retention_period = number
  })
  default = {
    engine         = "postgres"
    engine_version = "14.9"
    instance_class = "db.t3.micro"
    allocated_storage = 20
    multi_az      = true
    backup_retention_period = 7
  }
}

variable "enable_s3_buckets" {
  description = "Enable S3 buckets"
  type        = bool
  default     = true
}

variable "s3_bucket_configs" {
  description = "S3 bucket configurations"
  type = map(object({
    versioning_enabled = bool
    lifecycle_rules    = list(string)
    server_side_encryption = bool
  }))
  default = {
    backup = {
      versioning_enabled = true
      lifecycle_rules    = ["delete_old_versions"]
      server_side_encryption = true
    }
  }
}

variable "backup_retention_days" {
  description = "Backup retention in days"
  type        = number
  default     = 30
}

variable "enable_cross_region_backup" {
  description = "Enable cross-region backup"
  type        = bool
  default     = true
}

variable "enable_encryption_at_rest" {
  description = "Enable encryption at rest"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for encryption"
  type        = string
  default     = null
}

# Automation Variables
variable "enable_auto_healing" {
  description = "Enable auto-healing automation"
  type        = bool
  default     = true
}

variable "enable_cost_optimization" {
  description = "Enable cost optimization automation"
  type        = bool
  default     = true
}

variable "enable_compliance_check" {
  description = "Enable compliance checking automation"
  type        = bool
  default     = true
}

variable "automation_schedules" {
  description = "Automation schedules (cron expressions)"
  type        = map(string)
  default = {
    cost_optimization = "0 3 * * *"  # Daily at 3 AM
    compliance_check  = "0 4 * * 1"  # Weekly on Monday at 4 AM
    backup_cleanup    = "0 5 * * 0"  # Weekly on Sunday at 5 AM
  }
}

variable "notification_topics" {
  description = "SNS topics for notifications"
  type        = map(string)
  default = {
    alerts     = "infrastructure-alerts"
    automation = "automation-notifications"
  }
}

variable "automation_role_policies" {
  description = "IAM policies for automation roles"
  type        = list(string)
  default = [
    "AutoScalingFullAccess",
    "EC2ReadOnlyAccess",
    "CloudWatchFullAccess"
  ]
}