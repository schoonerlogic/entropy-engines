# AWS Cloud-Specific Infrastructure Outputs

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnets
}

output "private_subnet_cidrs" {
  description = "List of private subnet CIDR blocks"
  value       = module.vpc.private_subnets_cidr_blocks
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnets
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "control_plane_security_group_id" {
  description = "Security group ID for control plane"
  value       = aws_security_group.control_plane.id
}

output "worker_nodes_security_group_id" {
  description = "Security group ID for worker nodes"
  value       = aws_security_group.worker_nodes.id
}

# output "bastion_security_group_id" {
#   description = "Security group ID for bastion host"
#   value       = aws_security_group.bastion.id
# }
#
# output "bastion_public_ip" {
#   description = "Public IP address of bastion host"
#   value       = var.enable_bastion_host ? aws_instance.bastion[0].public_ip : null
# }
#
# output "bastion_instance_id" {
#   description = "Instance ID of bastion host"
#   value       = var.enable_bastion_host ? aws_instance.bastion[0].id : null
# }

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = aws_iam_instance_profile.k8s_instance_profile.name
}

output "availability_zones" {
  description = "List of availability zones"
  value       = var.availability_zones
}

