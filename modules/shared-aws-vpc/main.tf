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
    # Add the 1Password provider
    onepassword = {
      source = "1Password/onepassword"
      # Check for the latest appropriate version on the Terraform Registry
      version = "~> 1.2"
    }
    # Ensure the GitHub provider is declared
    github = {
      source = "integrations/github"
      # Check for the latest appropriate version
      version = "~> 6.0"
    }
  }
  required_version = ">= 1.0.0" # Adding minimum Terraform version
}

provider "aws" {
  region = var.aws_region # Add reference to region variable
}

provider "onepassword" {
  service_account_token = var.onepassword_token
}

provider "github" {
  token = var.github_token
}

module "network" {
  source = "./modules/network"

  project      = var.project
  nat_type     = var.nat_type
  bastion_type = var.bastion_type
  ssh_key_name = var.ssh_key_name
  vpc_name     = var.vpc_name
  region       = var.aws_region
}

module "ssh_config" {
  source = "./modules/ssh-config"

  output_path          = "${path.module}/ssh_config"
  template_path        = "${path.module}/templates/ssh_config.tpl"
  project              = var.project
  ssh_private_key_path = var.ssh_private_key_path
  bastion_host         = module.network.bastion_host
  bastion_user         = var.bastion_user
}

module "iam" {
  source = "./modules/iam"

  project    = var.project
  aws_region = var.aws_region
  account_id = data.aws_caller_identity.current.account_id
}

data "aws_caller_identity" "current" {
  # This data source requires no configuration arguments.
}


module "vpc_endpoints" {
  source = "./modules/vpc-endpoints"

  vpc_id            = module.network.vpc_id
  subnet_ids        = module.network.private_subnet_ids
  route_table_ids   = module.network.private_route_table_ids
  security_group_id = module.network.vpc_endpoints_security_group_id
  region            = var.aws_region

  tags = {
    Environment = var.environment
    Terraform   = "true"
  }
}

