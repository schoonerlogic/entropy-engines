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

# Extract values from individual variables for easier access
locals {
  # Core values
  aws_region  = var.aws_region
  project     = var.project
  environment = var.environment
  vpc_name    = var.vpc_name

  bootstrap_bucket_name = var.bootstrap_bucket_name

  # Security values
  ssh_key_name = var.ssh_key_name

  # NAT configuration
  nat_type = var.nat_type

  # Determine bastion type from security config
  bastion_type = var.enable_bastion_host ? var.bastion_instance_type : "none"
}

provider "aws" {
  region = local.aws_region
}

resource "aws_s3_bucket" "worker_s3_bootstrap_bucket" {
  bucket = local.bootstrap_bucket_name
}

# Pass individual variables to submodules
module "network" {
  source = "./modules/network"

  # Core values
  project     = local.project
  vpc_name    = local.vpc_name
  region      = local.aws_region
  environment = local.environment

  # Network configuration - pass individual values
  vpc_cidr             = var.vpc_cidr
  kubernetes_cidrs     = var.kubernetes_cidrs
  availability_zones   = var.availability_zones
  public_subnet_count  = var.public_subnet_count
  private_subnet_count = var.private_subnet_count

  # Security config
  ssh_key_name          = var.ssh_key_name
  ssh_allowed_cidrs     = var.ssh_allowed_cidrs
  bastion_allowed_cidrs = var.bastion_allowed_cidrs
  enable_bastion_host   = var.enable_bastion_host
  bastion_type          = var.bastion_instance_type

  # NAT config
  nat_type           = var.nat_type
  single_nat_gateway = var.single_nat_gateway

  # Kubernetes config
  kubernetes_cluster_name = var.cluster_name
  enable_kubernetes_tags  = var.enable_kubernetes_tags
  enable_nats_messaging   = var.enable_nats_messaging
  nats_ports              = var.nats_ports
  enable_gpu_nodes        = var.enable_gpu_nodes
}

module "iam" {
  source = "./modules/iam"

  project                 = local.project
  aws_region              = local.aws_region
  account_id              = data.aws_caller_identity.current.account_id
  control_plane_role_name = var.control_plane_role_name
  worker_role_name        = var.worker_role_name
  gpu_worker_role_name    = var.gpu_worker_role_name
  bootstrap_bucket_name   = var.bootstrap_bucket_name
}

data "aws_caller_identity" "current" {}

module "vpc_endpoints" {
  source = "./modules/vpc-endpoints"

  vpc_id            = module.network.vpc_id
  subnet_ids        = module.network.private_subnet_ids
  route_table_ids   = module.network.private_route_table_ids
  security_group_id = module.network.vpc_endpoints_security_group_id
  region            = local.aws_region

  # Pass cost optimization settings as individual variables
  enable_spot_instances = var.enable_spot_instances
  enable_vpc_endpoints  = var.enable_vpc_endpoints

  tags = {
    Environment = local.environment
    Project     = local.project
    Terraform   = "true"
  }
}
