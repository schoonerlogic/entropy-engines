# modules/network/outputs.tf
# Updated to handle conditional resources safely

#===============================================================================
# AMI Output
#===============================================================================

output "base_aws_ami" {
  description = "Default operating system AMI"
  value       = data.aws_ami.ubuntu
}

#===============================================================================
# VPC Outputs (from terraform-aws-modules/vpc/aws)
#===============================================================================

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "private_subnet_cidrs" {
  description = "List of CIDR blocks of private subnets"
  value       = module.vpc.private_subnets_cidr_blocks
}

output "public_subnet_ids" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}

output "public_subnet_cidrs" {
  description = "List of CIDR blocks of public subnets"
  value       = module.vpc.public_subnets_cidr_blocks
}

output "availability_zones_used" {
  description = "List of Availability Zones used for the subnets"
  value       = local.azs
}

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway"
  value       = module.vpc.igw_id
}

output "default_security_group_id" {
  description = "The ID of the default security group for the VPC"
  value       = module.vpc.default_security_group_id
}

output "private_route_table_ids" {
  description = "List of IDs of private route tables"
  value       = module.vpc.private_route_table_ids
}

output "public_route_table_ids" {
  description = "List of IDs of public route tables"
  value       = module.vpc.public_route_table_ids
}

#===============================================================================
# NAT Gateway Outputs (from VPC module)
#===============================================================================

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = module.vpc.natgw_ids
}

output "nat_gateway_public_ips" {
  description = "List of public IP addresses for the NAT Gateways"
  value       = module.vpc.nat_public_ips
}

# output "nat_gateway_eip_allocation_ids" {
#   description = "List of EIP Allocation IDs for the NAT Gateways"
#   value       = module.vpc.nat_eip_ids
# }

#===============================================================================
# Bastion Host Outputs (conditional)
#===============================================================================

output "bastion_instance_id" {
  description = "The ID of the Bastion host instance"
  value       = var.enable_bastion_host ? aws_instance.bastion[0].id : null
}

output "bastion_public_ip" {
  description = "The public IP address of the Bastion host"
  value       = var.enable_bastion_host ? aws_instance.bastion[0].public_ip : null
}

output "bastion_private_ip" {
  description = "The private IP address of the Bastion host"
  value       = var.enable_bastion_host ? aws_instance.bastion[0].private_ip : null
}

output "bastion_host" {
  description = "Instance on public subnet to access private subnets"
  value       = var.enable_bastion_host ? aws_instance.bastion : []
}

#===============================================================================
# Security Group Outputs
#===============================================================================

output "control_plane_security_group_id" {
  description = "The ID of the Kubernetes control plane security group"
  value       = aws_security_group.control_plane.id
}

output "worker_nodes_security_group_id" {
  description = "The ID of the Kubernetes worker nodes security group"
  value       = aws_security_group.worker_nodes.id
}

output "tooling_security_group_id" {
  description = "The ID of the tooling security group"
  value       = aws_security_group.tooling.id
}

output "bastion_host_security_group_id" {
  description = "The ID of the Bastion host security group"
  value       = aws_security_group.bastion_host.id
}

output "vpc_endpoints_security_group_id" {
  description = "The ID of the VPC endpoints security group"
  value       = var.enable_vpc_endpoints ? aws_security_group.vpc_endpoints[0].id : null
}

output "nats_security_group_id" {
  description = "The ID of the NATS messaging security group"
  value       = var.enable_nats_messaging ? aws_security_group.nats_messaging[0].id : null
}

output "gpu_nodes_security_group_id" {
  description = "The ID of the GPU nodes security group"
  value       = var.enable_gpu_nodes ? aws_security_group.k8s_gpu_nodes[0].id : null
}

#===============================================================================
# Kubernetes Configuration Outputs
#===============================================================================

output "environment" {
  description = "The environment tag for this network"
  value       = var.environment
}

output "pod_cidr_block" {
  description = "The CIDR block intended for Pods in the Kubernetes cluster"
  value       = local.pod_cidr_block
}

output "service_cidr_block" {
  description = "The CIDR block intended for Services in the Kubernetes cluster"
  value       = local.service_cidr_block
}

output "cluster_dns_ip" {
  description = "The calculated IP address for the cluster DNS service (e.g., CoreDNS)"
  value       = local.cluster_dns_ip
}

output "cluster_name" {
  description = "The Kubernetes cluster name used for tagging"
  value       = local.cluster_name
}
