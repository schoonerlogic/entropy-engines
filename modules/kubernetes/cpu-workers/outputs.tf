# modules/kubernetes/cpu-workers/outputs.tf
# Outputs for CPU worker module

#===============================================================================
# Infrastructure Outputs (from worker-base module)
#===============================================================================

output "asg_name" {
  description = "Name of the CPU worker Auto Scaling Group"
  value       = module.cpu_worker_base.asg_name
}

output "asg_arn" {
  description = "ARN of the CPU worker Auto Scaling Group"
  value       = module.cpu_worker_base.asg_arn
}

output "asg_desired_capacity" {
  description = "Desired capacity of the CPU worker Auto Scaling Group"
  value       = module.cpu_worker_base.asg_desired_capacity
}

output "launch_template_id" {
  description = "ID of the CPU worker launch template"
  value       = module.cpu_worker_base.launch_template_id
}

output "launch_template_arn" {
  description = "ARN of the CPU worker launch template"
  value       = module.cpu_worker_base.launch_template_arn
}

output "launch_template_latest_version" {
  description = "Latest version of the CPU worker launch template"
  value       = module.cpu_worker_base.launch_template_latest_version
}

#===============================================================================
# IAM Outputs
#===============================================================================

output "instance_profile_name" {
  description = "Name of the CPU worker instance profile"
  value       = module.cpu_worker_base.instance_profile_name
}

output "instance_profile_arn" {
  description = "ARN of the CPU worker instance profile"
  value       = module.cpu_worker_base.instance_profile_arn
}

#===============================================================================
# Instance Outputs
#===============================================================================

output "instance_ids" {
  description = "List of CPU worker instance IDs"
  value       = module.cpu_worker_base.worker_instance_ids
}

output "instance_private_ips" {
  description = "List of CPU worker private IP addresses"
  value       = module.cpu_worker_base.worker_instance_private_ips
}

output "instance_public_ips" {
  description = "List of CPU worker public IP addresses"
  value       = module.cpu_worker_base.worker_instance_public_ips
}

output "instance_count" {
  description = "Total number of CPU worker instances"
  value       = module.cpu_worker_base.total_instance_count
}

#===============================================================================
# Configuration Outputs
#===============================================================================

output "cluster_name" {
  description = "Name of the Kubernetes cluster"
  value       = var.cluster_name
}

output "worker_type" {
  description = "Type of worker nodes"
  value       = "cpu"
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "kubernetes_user" {
  description = "Kubernetes operations user"
  value       = var.k8s_user
}

output "kubernetes_version_stream" {
  description = "Kubernetes version stream"
  value       = var.k8s_major_minor_stream
}

output "kubernetes_package_version" {
  description = "Kubernetes package version"
  value       = var.k8s_package_version_string
}

#===============================================================================
# Instance Configuration Outputs
#===============================================================================

output "instance_types" {
  description = "EC2 instance types configured for CPU workers"
  value       = var.cpu_instance_types
}

output "on_demand_count" {
  description = "Number of on-demand CPU worker instances"
  value       = var.cpu_on_demand_count
}

output "spot_count" {
  description = "Number of spot CPU worker instances"
  value       = var.cpu_spot_count
}

output "total_desired_count" {
  description = "Total desired number of CPU worker instances"
  value       = var.cpu_on_demand_count + var.cpu_spot_count
}

output "using_instance_requirements" {
  description = "Whether instance requirements are being used instead of specific instance types"
  value       = var.use_instance_requirements
}

#===============================================================================
# Network Configuration Outputs
#===============================================================================

output "subnet_ids" {
  description = "Subnet IDs where CPU workers are deployed"
  value       = var.subnet_ids
}

output "security_group_ids" {
  description = "Security group IDs assigned to CPU workers"
  value       = var.security_group_ids
}

output "ssh_key_name" {
  description = "SSH key name for CPU worker access"
  value       = var.ssh_key_name
}

#===============================================================================
# Script Management Outputs
#===============================================================================

output "scripts_uploaded" {
  description = "List of scripts uploaded to S3 for CPU workers"
  value       = keys(local.all_cpu_worker_scripts)
}

output "s3_script_keys" {
  description = "S3 keys for CPU worker scripts"
  value       = [for script in local.all_cpu_worker_scripts : script.s3_key]
}

output "shared_scripts" {
  description = "List of shared scripts used by CPU workers"
  value       = keys(local.shared_scripts)
}

output "cpu_specific_scripts" {
  description = "List of CPU worker-specific scripts"
  value       = keys(local.cpu_worker_scripts)
}

output "scripts_bucket_name" {
  description = "S3 bucket name containing the setup scripts"
  value       = var.k8s_scripts_bucket_name
}

#===============================================================================
# SSM Configuration Outputs
#===============================================================================

output "ssm_join_command_path" {
  description = "SSM Parameter Store path for the join command"
  value       = var.ssm_join_command_path
}

#===============================================================================
# Monitoring Outputs
#===============================================================================

output "cloudwatch_logs_enabled" {
  description = "Whether CloudWatch logging is enabled"
  value       = var.enable_cloudwatch_logs
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch Log Group name for CPU workers (if enabled)"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.cpu_worker_logs[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "CloudWatch Log Group ARN for CPU workers (if enabled)"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.cpu_worker_logs[0].arn : null
}

output "notifications_enabled" {
  description = "Whether SNS notifications are enabled"
  value       = var.enable_notifications
}

output "notification_topic_arn" {
  description = "SNS topic ARN for CPU worker notifications (if enabled)"
  value       = var.enable_notifications ? aws_sns_topic.cpu_worker_notifications[0].arn : null
}

#===============================================================================
# Tagging Outputs
#===============================================================================

output "worker_tag_key" {
  description = "Tag key used to identify CPU worker instances"
  value       = module.cpu_worker_base.worker_tag_key
}

output "worker_tag_value" {
  description = "Tag value used to identify CPU worker instances"
  value       = module.cpu_worker_base.worker_tag_value
}

output "common_tags" {
  description = "Common tags applied to CPU worker resources"
  value       = local.common_tags
}

#===============================================================================
# Advanced Configuration Outputs
#===============================================================================

output "ami_id" {
  description = "AMI ID used for CPU worker instances"
  value       = var.base_aws_ami
}

output "block_device_mappings" {
  description = "Block device mappings for CPU worker instances"
  value       = var.block_device_mappings
}

output "health_check_type" {
  description = "Health check type for the Auto Scaling Group"
  value       = var.health_check_type
}

output "health_check_grace_period" {
  description = "Health check grace period in seconds"
  value       = var.health_check_grace_period
}

output "spot_allocation_strategy" {
  description = "Spot instance allocation strategy"
  value       = var.spot_allocation_strategy
}

#===============================================================================
# Status and Metadata Outputs
#===============================================================================

output "deployment_timestamp" {
  description = "Timestamp when the CPU workers were deployed"
  value       = timestamp()
}

output "terraform_workspace" {
  description = "Terraform workspace used for deployment"
  value       = terraform.workspace
}

#===============================================================================
# Resource Summary Output
#===============================================================================

output "resource_summary" {
  description = "Summary of CPU worker resources created"
  value = {
    cluster_name          = var.cluster_name
    worker_type           = "cpu"
    environment           = var.environment
    total_instances       = var.cpu_on_demand_count + var.cpu_spot_count
    on_demand_instances   = var.cpu_on_demand_count
    spot_instances        = var.cpu_spot_count
    instance_types        = var.cpu_instance_types
    scripts_uploaded      = length(local.all_cpu_worker_scripts)
    shared_scripts        = length(local.shared_scripts)
    cpu_specific_scripts  = length(local.cpu_worker_scripts)
    monitoring_enabled    = var.enable_cloudwatch_logs
    notifications_enabled = var.enable_notifications
    asg_name              = module.cpu_worker_base.asg_name
    launch_template_id    = module.cpu_worker_base.launch_template_id
  }
}
