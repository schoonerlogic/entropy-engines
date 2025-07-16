# Cloud-Agnostic Infrastructure Configuration
# This file orchestrates the deployment of self-managed Kubernetes across clouds

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Variables


variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "agentic-platform"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Additional tags to apply to all AWS resources"
  type        = map(string)
  default     = {}
}

variable "single_nat_gateway" {
  description = "Use single NAT gateway for cost optimization"
  type        = bool
  default     = true
}

variable "nats_version" {
  description = "NATS server version"
  type        = string
}

variable "nats_instance_type" {
  description = "Instance type for NATS servers"
  type        = string
  default     = "t4g.small"
}



variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for cost optimization"
  type        = bool
  default     = true
}

variable "enable_volume_encryption" {
  description = "Enable EBS volume encryption"
  type        = bool
  default     = true
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "bastion_allowed_cidrs" {
  description = "CIDR blocks allowed for bastion access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.29.0"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "ssh_key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "enable_bastion_host" {
  description = "Enable creation of bastion host"
  type        = bool
  default     = false
}

# Control plane configuration
variable "control_plane_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 3
}

variable "control_plane_instance_type" {
  description = "Instance type for control plane"
  type        = string
  default     = "t3.medium"
}

# CPU worker configuration
variable "cpu_worker_count" {
  description = "Number of CPU worker nodes"
  type        = number
  default     = 2
}

variable "cpu_worker_instance_type" {
  description = "Instance type for CPU workers"
  type        = string
  default     = "m7g.large"
}

# GPU worker configuration
variable "gpu_worker_count" {
  description = "Number of GPU worker nodes"
  type        = number
  default     = 1
}

variable "gpu_worker_instance_type" {
  description = "Instance type for GPU workers"
  type        = string
  default     = "g5g.xlarge"
}

# Networking configuration
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "pod_cidr" {
  description = "Pod CIDR range"
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "Service CIDR range"
  type        = string
  default     = "10.96.0.0/12"
}

# Configure AWS provider
provider "aws" {
  region = var.aws_region
}

# Local values for AWS-specific configuration
locals {
  cloud_config = {
    region             = var.aws_region
    availability_zones = var.availability_zones
    instance_profile   = module.aws_infrastructure.iam_instance_profile_name
    security_group_ids = [
      module.aws_infrastructure.control_plane_security_group_id,
      module.aws_infrastructure.worker_nodes_security_group_id
    ]
    subnet_ids = module.aws_infrastructure.private_subnet_ids
    vpc_id     = module.aws_infrastructure.vpc_id
  }
}

# AWS Infrastructure (cloud-specific)
module "aws_infrastructure" {
  source = "./modules/cloud-specific/aws"

  cluster_name          = var.cluster_name
  environment           = var.environment
  vpc_cidr              = var.vpc_cidr
  availability_zones    = var.availability_zones
  single_nat_gateway    = var.single_nat_gateway
  ssh_allowed_cidrs     = var.ssh_allowed_cidrs
  bastion_allowed_cidrs = var.bastion_allowed_cidrs
  enable_bastion_host   = var.enable_bastion_host
  ssh_key_name          = var.ssh_key_name
  tags                  = var.tags
}
# Kubernetes cluster configuration (cloud-agnostic)
module "kubernetes_cluster" {
  source = "./modules/cloud-agnostic/kubernetes-cluster"

  cluster_name         = var.cluster_name
  pod_cidr             = var.pod_cidr
  service_cidr         = var.service_cidr
  ssh_key_name         = var.ssh_key_name
  subnet_ids           = module.aws_infrastructure.private_subnet_ids
  security_group_ids   = [module.aws_infrastructure.control_plane_security_group_id, module.aws_infrastructure.worker_nodes_security_group_id]
  iam_instance_profile = module.aws_infrastructure.iam_instance_profile_name
  cloud_provider       = "aws"
  cloud_config         = local.cloud_config
}

# Agent nodes (CPU and GPU)
module "agent_nodes" {
  source = "./modules/cloud-agnostic/agent-nodes"

  cluster_name   = var.cluster_name
  cloud_provider = "aws"
  cloud_config   = local.cloud_config

  # Control plane
  control_plane_count         = var.control_plane_count
  control_plane_instance_type = var.control_plane_instance_type
  control_plane_user_data     = module.kubernetes_cluster.control_plane_user_data

  # CPU workers
  cpu_worker_count         = var.cpu_worker_count
  cpu_worker_instance_type = var.cpu_worker_instance_type

  # GPU workers
  gpu_worker_count         = var.gpu_worker_count
  gpu_worker_instance_type = var.gpu_worker_instance_type

  worker_user_data   = module.kubernetes_cluster.worker_user_data
  ssh_key_name       = var.ssh_key_name
  kubernetes_version = var.kubernetes_version
  kubeadm_token      = module.kubernetes_cluster.kubeadm_token
  certificate_key    = module.kubernetes_cluster.certificate_key
}

# NATS messaging infrastructure
module "nats_messaging" {
  source = "./modules/cloud-agnostic/nats-messaging"

  cluster_name       = var.cluster_name
  cloud_provider     = "aws"
  cloud_config       = local.cloud_config
  nats_instance_type = var.nats_instance_type
}

# Outputs
output "cluster_endpoint" {
  description = "Kubernetes cluster endpoint"
  value       = module.aws_infrastructure.vpc_id
}

output "control_plane_ips" {
  description = "Private IP addresses of control plane nodes"
  value       = module.agent_nodes.control_plane_private_ips
}

output "cpu_worker_ips" {
  description = "Private IP addresses of CPU worker nodes"
  value       = module.agent_nodes.cpu_worker_private_ips
}

output "gpu_worker_ips" {
  description = "Private IP addresses of GPU worker nodes"
  value       = module.agent_nodes.gpu_worker_private_ips
}

output "nats_endpoint" {
  description = "NATS messaging endpoint"
  value       = module.nats_messaging.nats_endpoint
}

output "kubeconfig_command" {
  description = "Command to get kubeconfig from control plane"
  value       = "kubectl config use-context ${var.cluster_name}"
}

