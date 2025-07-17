
# modules/iam/outputs.tf

output "ec2_role_arn" {
  description = "The ARN of the general EC2 IAM role."
  value       = module.iam.ec2_role_arn
}

output "ec2_role_name" {
  description = "The name of the general EC2 IAM role."
  value       = module.iam.ec2_role_name
}

output "ec2_instance_profile_arn" {
  description = "The ARN of the EC2 instance profile."
  value       = module.iam.ec2_instance_profile_arn
}

output "ec2_instance_profile_name" {
  description = "The name of the EC2 instance profile."
  value       = module.iam.ec2_instance_profile_name
}

output "ec2_instance_connect_policy_arn" {
  description = "The ARN of the IAM policy for EC2 Instance Connect."
  value       = module.iam.ec2_instance_connect_policy_arn
}

output "spot_fleet_role_arn" {
  description = "The ARN of the IAM role for the EC2 Spot Fleet service."
  value       = module.iam.spot_fleet_role_arn
}

output "spot_fleet_role_name" {
  description = "The name of the IAM role for the EC2 Spot Fleet service."
  value       = module.iam.spot_fleet_role_name
}


# modules/network/outputs.tf

# --- VPC Outputs (from terraform-aws-modules/vpc/aws) ---
output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.network.vpc_id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.network.vpc_cidr_block
}

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

output "availability_zones_used" {
  description = "List of Availability Zones used for the subnets"
  value       = module.network.availability_zones_used
}

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway"
  value       = module.network.internet_gateway_id
}

output "default_security_group_id" {
  description = "The ID of the default security group for the VPC"
  value       = module.network.default_security_group_id
}

output "private_route_table_ids" {
  description = "List of IDs of private route tables"
  value       = module.network.private_route_table_ids
}

output "public_route_table_ids" {
  description = "List of IDs of public route tables"
  value       = module.network.public_route_table_ids
}


# --- NAT Gateway Outputs (conditional) ---
output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs (empty if NAT type is not 'gateway')"
  value       = module.network.nat_gateway_ids
}

output "nat_gateway_public_ips" {
  description = "List of public IP addresses for the NAT Gateways (empty if NAT type is not 'gateway')"
  value       = module.network.nat_gateway_public_ips
}

output "nat_gateway_eip_allocation_ids" {
  description = "List of EIP Allocation IDs for the NAT Gateways (empty if NAT type is not 'gateway')"
  value       = module.network.nat_gateway_eip_allocation_ids
}

# --- Bastion Host Outputs ---
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

# --- Security Group Outputs ---
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

# --- Other Useful Outputs ---

output "environment" {
  description = "The environment tag for this network"
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
  description = "The calculated IP address for the cluster DNS service (e.g., CoreDNS)"
  value       = module.network.cluster_dns_ip
}

output "bastion_host_public_ip" {
  description = "Instance on public subnet to access private subnets"
  value       = module.network.bastion_host[0].public_ip
}


