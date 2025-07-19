terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Adding version constraint
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4" # Adding version constraint
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5" # Adding version constraint for random provider
    }
  }
}

# Extract values from organized config objects for easier access
locals {
  # Core values
  aws_region  = var.core_config.aws_region
  project     = var.core_config.project
  environment = var.core_config.environment
  vpc_name    = var.core_config.vpc_name

  # Security values
  ssh_key_name = var.security_config.ssh_key_name

  # NAT configuration
  nat_type = var.nat_config.nat_type

  # Determine bastion type from security config
  bastion_type = var.security_config.enable_bastion_host ? var.security_config.bastion_instance_type : "none"
}

provider "aws" {
  region = local.aws_region
}


# Pass organized configs to submodules
module "network" {
  source = "./modules/network"

  # Core values
  project  = local.project
  vpc_name = local.vpc_name
  region   = local.aws_region
  environment = local.environment

  # Configuration objects - pass individual values
  vpc_cidr           = var.network_config.vpc_cidr
  kubernetes_cidrs   = var.network_config.kubernetes_cidrs
  availability_zones = var.network_config.availability_zones
  public_subnet_count  = var.network_config.public_subnet_count
  private_subnet_count = var.network_config.private_subnet_count
  
  # Security config
  ssh_key_name          = var.security_config.ssh_key_name
  ssh_allowed_cidrs     = var.security_config.ssh_allowed_cidrs
  bastion_allowed_cidrs = var.security_config.bastion_allowed_cidrs
  enable_bastion_host   = var.security_config.enable_bastion_host
  bastion_type          = var.security_config.bastion_instance_type
  
  # NAT config
  nat_type           = var.nat_config.nat_type
  single_nat_gateway = var.nat_config.single_nat_gateway
  
  # Kubernetes config
  kubernetes_cluster_name = var.kubernetes_config.cluster_name
  enable_kubernetes_tags  = var.kubernetes_config.enable_kubernetes_tags
  enable_nats_messaging   = var.kubernetes_config.enable_nats_messaging
  nats_ports              = var.kubernetes_config.nats_ports
  enable_gpu_nodes        = var.kubernetes_config.enable_gpu_nodes
}

module "iam" {
  source = "./modules/iam"

  project    = local.project
  aws_region = local.aws_region
  account_id = data.aws_caller_identity.current.account_id
}

data "aws_caller_identity" "current" {}

module "vpc_endpoints" {
  source = "./modules/vpc-endpoints"

  vpc_id            = module.network.vpc_id
  subnet_ids        = module.network.private_subnet_ids
  route_table_ids   = module.network.private_route_table_ids
  security_group_id = module.network.vpc_endpoints_security_group_id
  region            = local.aws_region

  # Pass cost optimization config
  cost_optimization = var.cost_optimization

  tags = {
    Environment = local.environment
    Project     = local.project
    Terraform   = "true"
  }
}
