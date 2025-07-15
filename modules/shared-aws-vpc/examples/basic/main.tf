# Basic AWS VPC Configuration
# Minimal setup for getting started

terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "my-app"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "ssh_key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

module "vpc" {
  source = "../../"

  project      = var.project_name
  environment  = var.environment
  vpc_name     = "${var.project_name}-${var.environment}-vpc"
  aws_region   = var.aws_region
  ssh_key_name = var.ssh_key_name

  # Security
  ssh_allowed_cidrs    = var.ssh_allowed_cidrs
  bastion_allowed_cidrs = var.ssh_allowed_cidrs

  # Basic features
  enable_nats_messaging = true
  enable_gpu_nodes      = false
  enable_vpc_endpoints  = true
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "control_plane_security_group_id" {
  value = module.vpc.control_plane_security_group_id
}

output "worker_nodes_security_group_id" {
  value = module.vpc.worker_nodes_security_group_id
}