# Main Infrastructure Outputs

# Cluster Information
output "cluster_endpoint" {
  description = "Kubernetes cluster endpoint"
  value       = module.aws_infrastructure.vpc_id
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.aws_infrastructure.vpc_id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.aws_infrastructure.private_subnet_ids
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.aws_infrastructure.public_subnet_ids
}

# Bastion Host
output "bastion_public_ip" {
  description = "Public IP address of bastion host"
  value       = module.aws_infrastructure.bastion_public_ip
}

output "bastion_instance_id" {
  description = "Instance ID of bastion host"
  value       = module.aws_infrastructure.bastion_instance_id
}

# Security Groups
output "control_plane_security_group_id" {
  description = "Security group ID for control plane"
  value       = module.aws_infrastructure.control_plane_security_group_id
}

output "worker_nodes_security_group_id" {
  description = "Security group ID for worker nodes"
  value       = module.aws_infrastructure.worker_nodes_security_group_id
}

# Kubernetes Configuration
output "kubeconfig_command" {
  description = "Command to configure kubectl"
  value       = "kubectl config use-context ${var.kubernetes_config.cluster_name}"
}

output "kubeadm_token" {
  description = "Kubeadm token for joining nodes (sensitive)"
  value       = "placeholder-token"
  sensitive   = true
}

output "certificate_key" {
  description = "Certificate key for joining control plane nodes (sensitive)"
  value       = "placeholder-key"
  sensitive   = true
}

output "k8s_scripts_bucket" {
  description = "Bucket for scripts to build the cluster"
  value       = module.aws_infrastructure.k8s_scripts_bucket_name
  sensitive   = false
}


