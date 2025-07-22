# modules/gpu-workers/outputs.tf

output "gpu_worker_info" {
  description = "Information about the GPU worker configuration"
  value       = local.gpu_worker_info
}

output "asg_name" {
  description = "Name of the GPU worker Auto Scaling Group"
  value       = module.gpu_worker_base.asg_name
}

output "launch_template_id" {
  description = "ID of the GPU worker launch template"
  value       = module.gpu_worker_base.launch_template_id
}

output "instance_profile_name" {
  description = "Name of the GPU worker IAM instance profile"
  value       = module.gpu_worker_base.instance_profile_name
}

output "instance_ids" {
  description = "List of GPU worker instance IDs"
  value       = module.gpu_worker_base.instance_ids
}

output "private_ips" {
  description = "Private IP addresses of the GPU worker instances."
  value       = module.gpu_worker_base.private_ips
}
