# modules/network/outputs.tf

# --- VPC Outputs (from terraform-aws-modules/vpc/aws) ---
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
  value       = module.vpc.private_subnets_cidr_blocks # Assuming the module outputs this, common for vpc module
}

output "public_subnet_ids" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}

output "public_subnet_cidrs" {
  description = "List of CIDR blocks of public subnets"
  value       = module.vpc.public_subnets_cidr_blocks # Assuming the module outputs this
}

output "availability_zones_used" {
  description = "List of Availability Zones used for the subnets"
  value       = local.azs # or module.vpc.azs if the module exposes the final list
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


# --- NAT Gateway Outputs (conditional) ---
output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs (empty if NAT type is not 'gateway')"
  value       = aws_nat_gateway.nat_gateway[*].id
}

output "nat_gateway_public_ips" {
  description = "List of public IP addresses for the NAT Gateways (empty if NAT type is not 'gateway')"
  value       = aws_eip.nat_eip[*].public_ip
}

output "nat_gateway_eip_allocation_ids" {
  description = "List of EIP Allocation IDs for the NAT Gateways (empty if NAT type is not 'gateway')"
  value       = aws_eip.nat_eip[*].id
}

# --- Bastion Host Outputs ---
output "bastion_instance_id" {
  description = "The ID of the Bastion host instance"
  value       = aws_instance.bastion.id
}

output "bastion_public_ip" {
  description = "The public IP address of the Bastion host"
  value       = aws_instance.bastion.public_ip
}

output "bastion_private_ip" {
  description = "The private IP address of the Bastion host"
  value       = aws_instance.bastion.private_ip
}

# --- Security Group Outputs ---
output "control_plane_security_group_id" {
  description = "The ID of the Kubernetes control plane security group"
  value       = aws_security_group.k8s_control_plane.id
}

output "worker_nodes_security_group_id" {
  description = "The ID of the Kubernetes worker nodes security group"
  value       = aws_security_group.k8s_nodes.id
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
  value       = aws_security_group.vpc_endpoints.id
}

# --- Other Useful Outputs ---

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

output "bastion_host" {
  description = "Instance on public subnet to access private subnets"
  value       = aws_instance.bastion
}
