# worker-base/outputs.tf
# Outputs for shared worker infrastructure

#===============================================================================
# Launch Template Outputs
#===============================================================================
output "launch_template_id" {
  description = "ID of the worker launch template"
  value       = aws_launch_template.worker_lt.id
}

output "launch_template_arn" {
  description = "ARN of the worker launch template"
  value       = aws_launch_template.worker_lt.arn
}

output "launch_template_latest_version" {
  description = "Latest version of the worker launch template"
  value       = aws_launch_template.worker_lt.latest_version
}

#===============================================================================
# Auto Scaling Group Outputs
#===============================================================================
output "asg_name" {
  description = "Name of the worker Auto Scaling Group"
  value       = length(aws_autoscaling_group.worker_asg) > 0 ? aws_autoscaling_group.worker_asg[0].name : null
}

output "asg_arn" {
  description = "ARN of the worker Auto Scaling Group"
  value       = length(aws_autoscaling_group.worker_asg) > 0 ? aws_autoscaling_group.worker_asg[0].arn : null
}

output "asg_desired_capacity" {
  description = "Desired capacity of the worker Auto Scaling Group"
  value       = length(aws_autoscaling_group.worker_asg) > 0 ? aws_autoscaling_group.worker_asg[0].desired_capacity : 0
}

#===============================================================================
# IAM Outputs
#===============================================================================
output "instance_profile_name" {
  description = "Name of the worker instance profile"
  value       = aws_iam_instance_profile.worker_profile.name
}

output "instance_profile_arn" {
  description = "ARN of the worker instance profile"
  value       = aws_iam_instance_profile.worker_profile.arn
}

#===============================================================================
# Instance Outputs
#===============================================================================
output "worker_instance_ids" {
  description = "List of worker instance IDs"
  value       = data.aws_instances.workers.ids
}

output "worker_instance_private_ips" {
  description = "List of worker instance private IP addresses"
  value       = data.aws_instances.workers.private_ips
}

output "worker_instance_public_ips" {
  description = "List of worker instance public IP addresses"
  value       = data.aws_instances.workers.public_ips
}

#===============================================================================
# Configuration Outputs
#===============================================================================
output "worker_type" {
  description = "Type of worker (cpu or gpu)"
  value       = var.worker_type
}

output "cluster_name" {
  description = "Name of the Kubernetes cluster"
  value       = var.cluster_name
}

output "total_instance_count" {
  description = "Total number of worker instances"
  value       = local.total_instance_count
}

output "worker_tag_key" {
  description = "Tag key used to identify worker instances"
  value       = local.worker_tag_key
}

output "worker_tag_value" {
  description = "Tag value used to identify worker instances"
  value       = local.worker_tag_value
}
