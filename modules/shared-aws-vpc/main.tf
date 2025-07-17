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
# terraform {
#   backend "s3" {
#     bucket = "infrastructure-at-rest-550834880252"
#     key    = "foundational-network/terraform.tfstate"
#     region = "us-east-1"
#
#     # Highly Recommended for team collaboration and safety:
#     # dynamodb_table = "terraform-state-locks"                  # REPLACE with your DynamoDB table name for state locking
#     # encrypt        = true                                     
#   }
# }

# module "network" {
#   source = "./modules/network"
#
#   project      = var.project
#   nat_type     = var.nat_type
#   bastion_type = var.bastion_type
#   ssh_key_name = var.ssh_key_name
#   vpc_name     = var.vpc_name
#   region       = var.aws_region
# }
#
# module "ssh_config" {
#   source = "./modules/ssh-config"
#
#   output_path          = "${path.module}/ssh_config"
#   template_path        = "${path.module}/templates/ssh_config.tpl"
#   project              = var.project
#   ssh_private_key_path = var.ssh_private_key_path
#   bastion_host         = module.network.bastion_host
#   bastion_user         = var.bastion_user
# }
#
# module "iam" {
#   source = "./modules/iam"
#
#   project    = var.project
#   aws_region = var.aws_region
#   account_id = data.aws_caller_identity.current.account_id
# }
#
# data "aws_caller_identity" "current" {
#   # This data source requires no configuration arguments.
# }
#
#
# module "vpc_endpoints" {
#   source = "./modules/vpc-endpoints"
#
#   vpc_id            = module.network.vpc_id
#   subnet_ids        = module.network.private_subnet_ids
#   route_table_ids   = module.network.private_route_table_ids
#   security_group_id = module.network.vpc_endpoints_security_group_id
#   region            = var.aws_region
#
#   tags = {
#     Environment = var.environment
#     Terraform   = "true"
#   }
# }

# Extract values from organized config objects for easier access
locals {
  # Core values
  aws_region  = var.core_config.aws_region
  project     = var.core_config.project
  environment = var.core_config.environment
  vpc_name    = var.core_config.vpc_name

  # Security values
  ssh_key_name = var.security_config.ssh_key_name

  # Legacy values (if you still need them)
  github_token         = var.legacy_config.github_token
  ssh_private_key_path = var.legacy_config.ssh_private_key_path

  # NAT configuration
  nat_type = var.nat_config.nat_type

  # Determine bastion type from security config
  bastion_type = var.security_config.enable_bastion_host ? var.security_config.bastion_instance_type : "none"
}

provider "aws" {
  region = local.aws_region
}

provider "github" {
  token = local.github_token
}

# Pass organized configs to submodules
module "network" {
  source = "./modules/network"

  # Core values
  project  = local.project
  vpc_name = local.vpc_name
  region   = local.aws_region

  # Configuration objects - pass entire objects to submodules
  network_config  = var.network_config
  security_config = var.security_config
  nat_config      = var.nat_config

  # Individual values for backward compatibility (if submodule expects them)
  nat_type     = local.nat_type
  bastion_type = local.bastion_type
  ssh_key_name = local.ssh_key_name
}

module "ssh_config" {
  source = "./modules/ssh-config"

  output_path          = "${path.module}/ssh_config"
  template_path        = "${path.module}/templates/ssh_config.tpl"
  project              = local.project
  ssh_private_key_path = local.ssh_private_key_path
  bastion_host         = module.network.bastion_host
  bastion_user         = "ubuntu" # You might want to add this to security_config
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
