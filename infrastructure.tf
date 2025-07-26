# Cloud-Agnostic Infrastructure Configuration
# This file orchestrates the deployment of self-managed Kubernetes across clouds

locals {
  common_tags = {
    Project     = "AgenticPlatform"
    Environment = var.core_config.environment
    ManagedBy   = "terraform"
  }
}


# Data source for Ubuntu AMI (used by spot-enabled modules)
# data "aws_ami" "ubuntu" {
#   most_recent = true
#   owners      = ["099720109477"] # Canonical
#
#   filter {
#     name   = "name"
#     values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*"]
#   }
#
#   filter {
#     name   = "virtualization-type"
#     values = ["hvm"]
#   }
# }
#

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name = "name"
    # More flexible wildcard matching (covers minor naming variations)
    values = [
      "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*",
    ]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# AWS Infrastructure (cloud-specific)
module "aws_infrastructure" {
  source = "./modules/infrastructure/cloud-specific/aws"

  # Core configuration
  aws_region  = var.core_config.aws_region
  environment = var.core_config.environment
  project     = var.core_config.project
  vpc_name    = var.core_config.vpc_name

  # IAM configuration
  control_plane_role_name = var.iam_config.control_plane_role_name
  worker_role_name        = var.iam_config.worker_role_name
  gpu_worker_role_name    = var.iam_config.gpu_worker_role_name

  # Network configuration
  base_aws_ami = data.aws_ami.ubuntu.id
  #  gpu_aws_ami           = var.network_config.gpu_aws_ami
  bootstrap_bucket_name = var.network_config.bootstrap_bucket_name
  vpc_cidr              = var.network_config.vpc_cidr
  kubernetes_cidrs      = var.network_config.kubernetes_cidrs
  cluster_dns_ip        = var.network_config.cluster_dns_ip
  availability_zones    = var.network_config.availability_zones
  public_subnet_count   = var.network_config.public_subnet_count
  private_subnet_count  = var.network_config.private_subnet_count
  subnet_ids            = var.network_config.subnet_ids
  iam_policy_version    = var.network_config.iam_policy_version

  # NAT configuration
  nat_type           = var.nat_config.nat_type
  single_nat_gateway = var.nat_config.single_nat_gateway

  # Security configuration
  ssh_allowed_cidrs     = var.security_config.ssh_allowed_cidrs
  bastion_allowed_cidrs = var.security_config.bastion_allowed_cidrs
  enable_bastion_host   = var.security_config.enable_bastion_host
  bastion_instance_type = var.security_config.bastion_instance_type
  bastion_host          = var.security_config.bastion_host
  bastion_user          = var.security_config.bastion_user
  ssh_public_key_path   = var.security_config.ssh_public_key_path
  ssh_private_key_path  = var.security_config.ssh_private_key_path
  ssh_key_name          = var.security_config.ssh_key_name
  security_group_ids    = var.security_config.security_group_ids

  # Kubernetes configuration
  enable_kubernetes_tags = var.kubernetes_config.enable_kubernetes_tags
  cluster_name           = var.kubernetes_config.cluster_name
  enable_nats_messaging  = var.kubernetes_config.enable_nats_messaging
  k8s_user               = var.kubernetes_config.k8s_user
  k8s_major_minor_stream = var.kubernetes_config.k8s_major_minor_stream
  k8s_full_patch_version = var.kubernetes_config.k8s_full_patch_version
  k8s_apt_package_suffix = var.kubernetes_config.k8s_apt_package_suffix
  enable_gpu_nodes       = var.kubernetes_config.enable_gpu_nodes
  nats_ports             = var.kubernetes_config.nats_ports
}
