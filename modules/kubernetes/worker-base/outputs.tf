# modules/worker-base/outputs.tf

output "instance_ids" {
  description = "List of worker instance IDs"
  value       = data.aws_instances.workers.ids
}

output "private_ips" {
  description = "List of worker private IP addresses"
  value       = data.aws_instances.workers.private_ips
}

output "asg_name" {
  description = "Name of the worker Auto Scaling Group"
  value       = length(aws_autoscaling_group.worker_asg) > 0 ? aws_autoscaling_group.worker_asg[0].name : null
}

output "launch_template_id" {
  description = "ID of the worker launch template"
  value       = aws_launch_template.worker_lt.id
}

output "instance_profile_name" {
  description = "Name of the worker IAM instance profile"
  value       = aws_iam_instance_profile.worker_profile.name
}
