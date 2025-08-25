# Outputs - Infrastructure Resource Information

# Networking Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.networking.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.networking.private_subnet_ids
}

output "database_subnet_ids" {
  description = "IDs of the database subnets"
  value       = module.networking.database_subnet_ids
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = module.networking.internet_gateway_id
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways"
  value       = module.networking.nat_gateway_ids
}

# Security Outputs
output "security_group_ids" {
  description = "Map of security group IDs"
  value = {
    vault      = module.security.vault_security_group_id
    app        = module.security.app_security_group_id
    lb         = module.security.lb_security_group_id
    monitoring = module.security.monitoring_security_group_id
  }
}

output "ssl_certificate_arn" {
  description = "ARN of the SSL certificate"
  value       = module.security.ssl_certificate_arn
}

output "waf_web_acl_id" {
  description = "ID of the WAF Web ACL"
  value       = module.security.waf_web_acl_id
}

# Vault Outputs
output "vault_cluster_info" {
  description = "Vault cluster information"
  value = {
    cluster_id           = module.vault.cluster_id
    load_balancer_dns    = module.vault.load_balancer_dns
    instance_ids         = module.vault.instance_ids
    auto_scaling_group   = module.vault.auto_scaling_group_name
    storage_backend      = var.vault_storage_type
    version             = var.vault_version
  }
  sensitive = false
}

output "vault_endpoints" {
  description = "Vault endpoint URLs"
  value = {
    internal = module.vault.internal_endpoint
    external = module.vault.external_endpoint
    api_url  = "https://${module.vault.load_balancer_dns}:8200"
    ui_url   = "https://${module.vault.load_balancer_dns}:8200/ui"
  }
}

output "vault_unseal_keys" {
  description = "Vault unseal key information (for manual unsealing if needed)"
  value = {
    auto_unseal_enabled = var.vault_enable_auto_unseal
    kms_key_id         = module.vault.kms_unseal_key_id
  }
  sensitive = true
}

# Compute Outputs
output "load_balancer_info" {
  description = "Load balancer information"
  value = {
    application_lb_dns = try(module.compute.application_lb_dns, null)
    network_lb_dns     = try(module.compute.network_lb_dns, null)
    application_lb_arn = try(module.compute.application_lb_arn, null)
    network_lb_arn     = try(module.compute.network_lb_arn, null)
  }
}

output "auto_scaling_groups" {
  description = "Auto Scaling Group information"
  value = {
    app_asg_name     = try(module.compute.app_asg_name, null)
    app_asg_arn      = try(module.compute.app_asg_arn, null)
    min_size         = var.min_capacity
    max_size         = var.max_capacity
    desired_capacity = var.desired_capacity
  }
}

output "nomad_cluster_info" {
  description = "Nomad cluster information"
  value = var.enable_nomad_cluster ? {
    cluster_endpoint = module.compute.nomad_cluster_endpoint
    datacenter      = var.nomad_datacenter
    version         = var.nomad_version
    ui_url          = "https://${module.compute.nomad_cluster_endpoint}:4646"
  } : null
}

output "ecs_cluster_info" {
  description = "ECS cluster information"
  value = var.enable_ecs_cluster ? {
    cluster_name = module.compute.ecs_cluster_name
    cluster_arn  = module.compute.ecs_cluster_arn
  } : null
}

output "eks_cluster_info" {
  description = "EKS cluster information"
  value = var.enable_eks_cluster ? {
    cluster_name     = module.compute.eks_cluster_name
    cluster_endpoint = module.compute.eks_cluster_endpoint
    cluster_arn      = module.compute.eks_cluster_arn
    version         = module.compute.eks_cluster_version
  } : null
}

# Monitoring Outputs
output "monitoring_endpoints" {
  description = "Monitoring service endpoints"
  value = {
    prometheus_url = var.enable_prometheus ? "http://${module.monitoring.prometheus_endpoint}:9090" : null
    grafana_url    = var.enable_grafana ? "https://${module.monitoring.grafana_endpoint}:3000" : null
    alertmanager_url = var.enable_alertmanager ? "http://${module.monitoring.alertmanager_endpoint}:9093" : null
    elasticsearch_url = var.enable_elasticsearch ? "https://${module.monitoring.elasticsearch_endpoint}:9200" : null
  }
}

output "monitoring_dashboards" {
  description = "Pre-configured dashboard URLs"
  value = var.enable_grafana ? {
    infrastructure = "https://${module.monitoring.grafana_endpoint}:3000/d/infrastructure"
    vault         = "https://${module.monitoring.grafana_endpoint}:3000/d/vault"
    traefik       = "https://${module.monitoring.grafana_endpoint}:3000/d/traefik"
    nomad         = "https://${module.monitoring.grafana_endpoint}:3000/d/nomad"
    system        = "https://${module.monitoring.grafana_endpoint}:3000/d/system"
  } : {}
}

# Storage Outputs
output "database_info" {
  description = "Database information"
  value = var.enable_rds ? {
    endpoint          = module.storage.db_endpoint
    port             = module.storage.db_port
    database_name    = module.storage.db_name
    parameter_group  = module.storage.db_parameter_group
    option_group     = module.storage.db_option_group
    backup_retention = var.db_config.backup_retention_period
  } : null
  sensitive = false
}

output "s3_bucket_info" {
  description = "S3 bucket information"
  value = var.enable_s3_buckets ? {
    bucket_names = module.storage.s3_bucket_names
    bucket_arns  = module.storage.s3_bucket_arns
    bucket_regions = module.storage.s3_bucket_regions
  } : {}
}

# Automation Outputs
output "automation_functions" {
  description = "Automation Lambda function information"
  value = {
    auto_healing_function    = var.enable_auto_healing ? module.automation.auto_healing_function_name : null
    cost_optimization_function = var.enable_cost_optimization ? module.automation.cost_optimization_function_name : null
    compliance_check_function = var.enable_compliance_check ? module.automation.compliance_check_function_name : null
  }
}

output "automation_schedules" {
  description = "Automation schedule information"
  value = {
    cost_optimization = var.automation_schedules.cost_optimization
    compliance_check  = var.automation_schedules.compliance_check
    backup_cleanup    = var.automation_schedules.backup_cleanup
  }
}

output "sns_topics" {
  description = "SNS topic information"
  value = {
    alerts_topic_arn     = module.automation.alerts_topic_arn
    automation_topic_arn = module.automation.automation_topic_arn
  }
}

# Environment Information
output "environment_info" {
  description = "Environment configuration summary"
  value = {
    project_name       = var.project_name
    environment        = var.environment
    aws_region         = var.aws_region
    compliance_level   = var.compliance_level
    backup_enabled     = var.backup_required == "yes"
    encryption_enabled = var.enable_encryption_at_rest
    monitoring_enabled = var.enable_cloudwatch_monitoring || var.enable_datadog_monitoring
    auto_scaling_enabled = var.enable_auto_scaling
    high_availability = var.vault_nodes >= 3 && length(var.private_subnet_cidrs) >= 2
  }
}

# Resource Counts and Costs
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    total_subnets = length(var.public_subnet_cidrs) + length(var.private_subnet_cidrs) + length(var.database_subnet_cidrs)
    vault_nodes   = var.vault_nodes
    min_app_instances = var.min_capacity
    max_app_instances = var.max_capacity
    storage_backends = compact([
      var.enable_rds ? "RDS" : "",
      var.enable_s3_buckets ? "S3" : "",
      var.vault_storage_type
    ])
    monitoring_stack = compact([
      var.enable_prometheus ? "Prometheus" : "",
      var.enable_grafana ? "Grafana" : "",
      var.enable_alertmanager ? "AlertManager" : "",
      var.enable_elasticsearch ? "Elasticsearch" : ""
    ])
  }
}

# Quick Access URLs
output "quick_access" {
  description = "Quick access URLs for services"
  value = {
    vault_ui     = "https://${module.vault.load_balancer_dns}:8200/ui"
    grafana      = var.enable_grafana ? "https://${module.monitoring.grafana_endpoint}:3000" : "Not enabled"
    prometheus   = var.enable_prometheus ? "http://${module.monitoring.prometheus_endpoint}:9090" : "Not enabled"
    traefik_dashboard = var.enable_nomad_cluster ? "https://${module.compute.nomad_cluster_endpoint}:8080/dashboard/" : "Not enabled"
    application_lb = try("https://${module.compute.application_lb_dns}", "Not enabled")
  }
}

# Security Information
output "security_summary" {
  description = "Security configuration summary"
  value = {
    waf_enabled           = var.enable_waf
    ssl_certificates      = length(var.domain_names) > 0
    vpc_flow_logs        = var.enable_vpc_flow_logs
    encryption_at_rest   = var.enable_encryption_at_rest
    auto_unseal_enabled  = var.vault_enable_auto_unseal
    backup_encryption    = var.enable_encryption_at_rest
    security_groups_count = length(var.security_groups)
  }
}

# Disaster Recovery Information
output "disaster_recovery_info" {
  description = "Disaster recovery configuration"
  value = {
    vault_snapshots_enabled = var.vault_enable_snapshots
    cross_region_backup    = var.enable_cross_region_backup
    backup_retention_days  = var.backup_retention_days
    multi_az_database     = var.enable_rds ? var.db_config.multi_az : false
    auto_scaling_enabled  = var.enable_auto_scaling
    availability_zones    = length(data.aws_availability_zones.available.names)
  }
}