# modules/infrastructure/cloud-specific/aws/outputs.tf

#===============================================================================
# Network Module Outputs
#===============================================================================

# VPC Outputs
output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.network.vpc_id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.network.vpc_cidr_block
}

# Subnet Outputs
output "private_subnet_ids" {
  description = "List of IDs of private subnets"
  value       = module.network.private_subnet_ids
}

output "private_subnet_cidrs" {
  description = "List of CIDR blocks of private subnets"
  value       = module.network.private_subnet_cidrs
}

output "public_subnet_ids" {
  description = "List of IDs of public subnets"
  value       = module.network.public_subnet_ids
}

output "public_subnet_cidrs" {
  description = "List of CIDR blocks of public subnets"
  value       = module.network.public_subnet_cidrs
}

# Availability Zones
output "availability_zones_used" {
  description = "List of Availability Zones used for the subnets"
  value       = module.network.availability_zones_used
}

# Gateway Outputs
output "internet_gateway_id" {
  description = "The ID of the Internet Gateway"
  value       = module.network.internet_gateway_id
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = module.network.nat_gateway_ids
}

output "nat_gateway_public_ips" {
  description = "List of public IP addresses for the NAT Gateways"
  value       = module.network.nat_gateway_public_ips
}

# Route Table Outputs
output "private_route_table_ids" {
  description = "List of IDs of private route tables"
  value       = module.network.private_route_table_ids
}

output "public_route_table_ids" {
  description = "List of IDs of public route tables"
  value       = module.network.public_route_table_ids
}

#===============================================================================
# Security Group Outputs
#===============================================================================

output "control_plane_security_group_id" {
  description = "The ID of the Kubernetes control plane security group"
  value       = module.network.control_plane_security_group_id
}

output "worker_nodes_security_group_id" {
  description = "The ID of the Kubernetes worker nodes security group"
  value       = module.network.worker_nodes_security_group_id
}

output "tooling_security_group_id" {
  description = "The ID of the tooling security group"
  value       = module.network.tooling_security_group_id
}

output "bastion_host_security_group_id" {
  description = "The ID of the Bastion host security group"
  value       = module.network.bastion_host_security_group_id
}

output "vpc_endpoints_security_group_id" {
  description = "The ID of the VPC endpoints security group"
  value       = module.network.vpc_endpoints_security_group_id
}

output "nats_security_group_id" {
  description = "The ID of the NATS messaging security group"
  value       = module.network.nats_security_group_id
}

output "default_security_group_id" {
  description = "The ID of the default security group for the VPC"
  value       = module.network.default_security_group_id
}

#===============================================================================
# Bastion Host Outputs
#===============================================================================

output "bastion_instance_id" {
  description = "The ID of the Bastion host instance"
  value       = module.network.bastion_instance_id
}

output "bastion_public_ip" {
  description = "The public IP address of the Bastion host"
  value       = module.network.bastion_public_ip
}

output "bastion_private_ip" {
  description = "The private IP address of the Bastion host"
  value       = module.network.bastion_private_ip
}

#===============================================================================
# IAM Module Outputs
#===============================================================================

output "ec2_role_arn" {
  description = "The ARN of the general EC2 IAM role"
  value       = module.iam.ec2_role_arn
}

output "ec2_role_name" {
  description = "The name of the general EC2 IAM role"
  value       = module.iam.ec2_role_name
}

output "ec2_instance_profile_arn" {
  description = "The ARN of the EC2 instance profile"
  value       = module.iam.ec2_instance_profile_arn
}

output "ec2_instance_profile_name" {
  description = "The name of the EC2 instance profile"
  value       = module.iam.ec2_instance_profile_name
}

output "control_plane_role" {
  description = "Role name for use with k8s cloud control plane"
  value       = module.iam.control_plane_role
}

output "spot_fleet_role_arn" {
  description = "The ARN of the IAM role for the EC2 Spot Fleet service"
  value       = module.iam.spot_fleet_role_arn
}

output "spot_fleet_role_name" {
  description = "The name of the IAM role for the EC2 Spot Fleet service"
  value       = module.iam.spot_fleet_role_name
}

#===============================================================================
# Kubernetes Configuration Outputs
#===============================================================================

output "environment" {
  description = "The environment tag for this infrastructure"
  value       = module.network.environment
}

output "pod_cidr_block" {
  description = "The CIDR block intended for Pods in the Kubernetes cluster"
  value       = module.network.pod_cidr_block
}

output "service_cidr_block" {
  description = "The CIDR block intended for Services in the Kubernetes cluster"
  value       = module.network.service_cidr_block
}

output "cluster_dns_ip" {
  description = "The calculated IP address for the cluster DNS service"
  value       = module.network.cluster_dns_ip
}

#===============================================================================
# S3 Bootstrap Bucket Outputs
#===============================================================================

output "bootstrap_bucket_name" {
  description = "Name of the S3 bucket used for worker bootstrap"
  value       = aws_s3_bucket.worker_s3_bootstrap_bucket.id
}

output "bootstrap_bucket_arn" {
  description = "ARN of the S3 bucket used for worker bootstrap"
  value       = aws_s3_bucket.worker_s3_bootstrap_bucket.arn
}
