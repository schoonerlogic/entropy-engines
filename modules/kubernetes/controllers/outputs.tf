# modules/controllers/outputs.tf
# Outputs from the controllers module

#===============================================================================
# Instance Information
#===============================================================================

output "instance_ids" {
  description = "List of controller instance IDs"
  value       = data.aws_instances.controllers.ids
}

output "private_ips" {
  description = "List of controller private IP addresses"
  value       = data.aws_instances.controllers.private_ips
}

output "primary_controller_ip" {
  description = "Private IP address of the primary controller"
  value       = length(data.aws_instances.controllers.private_ips) > 0 ? data.aws_instances.controllers.private_ips[0] : null
}

#===============================================================================
# Auto Scaling Group Information
#===============================================================================

output "asg_name" {
  description = "Name of the controllers Auto Scaling Group"
  value       = length(aws_autoscaling_group.controller_asg) > 0 ? aws_autoscaling_group.controller_asg[0].name : null
}

output "asg_arn" {
  description = "ARN of the controllers Auto Scaling Group"
  value       = length(aws_autoscaling_group.controller_asg) > 0 ? aws_autoscaling_group.controller_asg[0].arn : null
}

output "asg_desired_capacity" {
  description = "Desired capacity of the controllers ASG"
  value       = length(aws_autoscaling_group.controller_asg) > 0 ? aws_autoscaling_group.controller_asg[0].desired_capacity : 0
}

#===============================================================================
# Launch Template Information
#===============================================================================

output "launch_template_id" {
  description = "ID of the controllers launch template"
  value       = aws_launch_template.controller_lt.id
}

output "launch_template_arn" {
  description = "ARN of the controllers launch template"
  value       = aws_launch_template.controller_lt.arn
}

output "launch_template_name" {
  description = "Name of the controllers launch template"
  value       = aws_launch_template.controller_lt.name
}

#===============================================================================
# IAM Information
#===============================================================================

output "instance_profile_name" {
  description = "Name of the controllers IAM instance profile"
  value       = aws_iam_instance_profile.controller_profile.name
}

output "instance_profile_arn" {
  description = "ARN of the controllers IAM instance profile"
  value       = aws_iam_instance_profile.controller_profile.arn
}

#===============================================================================
# Cluster Information
#===============================================================================

output "cluster_name" {
  description = "Name of the Kubernetes cluster"
  value       = local.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint (primary controller IP)"
  value       = length(data.aws_instances.controllers.private_ips) > 0 ? "https://${data.aws_instances.controllers.private_ips[0]}:6443" : null
}

#===============================================================================
# SSM Parameter Information
#===============================================================================

output "ssm_join_command_path" {
  description = "SSM parameter path for worker join command"
  value       = local.ssm_join_command_path
}

output "ssm_certificate_key_path" {
  description = "SSM parameter path for certificate key"
  value       = local.ssm_certificate_key_path
}

output "ssm_parameter_arns" {
  description = "ARNs of SSM parameters created by the control plane"
  value       = local.ssm_parameters_arns
}

#===============================================================================
# Configuration Summary
#===============================================================================

output "controller_config_summary" {
  description = "Summary of controller configuration"
  value = {
    cluster_name       = local.cluster_name
    total_instances    = local.total_instance_count
    on_demand_count    = local.on_demand_count
    spot_count         = local.spot_count
    instance_types     = local.instance_types
    kubernetes_version = "${local.k8s_major_minor_stream}.x"

    # Network configuration
    pod_cidr_block     = local.pod_cidr_block
    service_cidr_block = local.service_cidr_block

    # ASG configuration
    health_check_grace_period = var.health_check_grace_period
    min_healthy_percentage    = var.min_healthy_percentage

    # Environment
    environment = local.environment

    # Tags
    additional_tags = var.additional_tags
  }
}

#===============================================================================
# Bootstrap Information
#===============================================================================
output "k9s_scripts_bucket" {
  description = "S3 URI of the control plane bootstrap bucket"
  value       = "s3://${var.k8s_scripts_bucket_name}"
}

output "bootstrap_script_s3_uri" {
  description = "S3 URI of the control plane bootstrap script"
  value       = "s3://${aws_s3_object.control_plane_setup_scripts["01-install-user-and-tooling"].bucket}/${aws_s3_object.control_plane_setup_scripts["01-install-user-and-tooling"].key}"
}

output "bootstrap_script_etag" {
  description = "ETag of the control plane bootstrap script in S3"
  value       = aws_s3_object.control_plane_setup_scripts["01-install-user-and-tooling"].etag
}

output "self_bootstrapping" {
  description = "Indicates that control plane uses self-bootstrapping (no provisioners)"
  value       = true
}

