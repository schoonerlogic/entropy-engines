# Agent Nodes Module Outputs

output "control_plane_private_ips" {
  description = "Private IP addresses of control plane nodes"
  value       = var.cloud_provider == "aws" ? aws_instance.control_plane[*].private_ip : []
}

output "cpu_worker_private_ips" {
  description = "Private IP addresses of CPU worker nodes"
  value       = var.cloud_provider == "aws" ? aws_instance.cpu_worker[*].private_ip : []
}

output "gpu_worker_private_ips" {
  description = "Private IP addresses of GPU worker nodes"
  value       = var.cloud_provider == "aws" ? aws_instance.gpu_worker[*].private_ip : []
}

output "control_plane_public_ips" {
  description = "Public IP addresses of control plane nodes"
  value       = var.cloud_provider == "aws" ? aws_instance.control_plane[*].public_ip : []
}

output "cpu_worker_public_ips" {
  description = "Public IP addresses of CPU worker nodes"
  value       = var.cloud_provider == "aws" ? aws_instance.cpu_worker[*].public_ip : []
}

output "gpu_worker_public_ips" {
  description = "Public IP addresses of GPU worker nodes"
  value       = var.cloud_provider == "aws" ? aws_instance.gpu_worker[*].public_ip : []
}
