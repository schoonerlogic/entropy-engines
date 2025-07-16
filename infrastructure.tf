# Cloud-Agnostic Infrastructure Configuration
# This file orchestrates the deployment of self-managed Kubernetes across clouds

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

# Configure AWS provider
provider "aws" {
  region = var.aws_region
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

# Agent nodes (CPU and GPU) - Create instances first
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

# Kubernetes cluster configuration (cloud-agnostic)
module "kubernetes_cluster" {
  source = "./modules/cloud-agnostic/kubernetes-cluster"

  cluster_name                 = var.cluster_name
  pod_cidr                     = var.pod_cidr
  service_cidr                 = var.service_cidr
  ssh_key_name                 = var.ssh_key_name
  subnet_ids                   = module.aws_infrastructure.private_subnet_ids
  security_group_ids           = [module.aws_infrastructure.control_plane_security_group_id, module.aws_infrastructure.worker_nodes_security_group_id]
  iam_instance_profile         = module.aws_infrastructure.iam_instance_profile_name
  cloud_provider               = "aws"
  cloud_config                 = local.cloud_config
  kubernetes_version           = var.kubernetes_version
  control_plane_private_ip     = cidrhost(module.aws_infrastructure.private_subnet_cidrs[0], 37)
  discovery_token_ca_cert_hash = "sha256:399a2eb369c7bd7b1f84a77d68e005a933eb4ee7e05db12f23fc69535d598e66"
}

# NATS messaging infrastructure
module "nats_messaging" {
  source = "./modules/cloud-agnostic/nats-messaging"

  cluster_name       = var.cluster_name
  cloud_provider     = "aws"
  cloud_config       = local.cloud_config
  nats_instance_type = var.nats_instance_type
  nats_version       = var.nats_version
}

# SSH configuration
resource "local_file" "ssh_config" {
  filename = "${path.root}/ssh_config"
  content = templatefile("${path.module}/modules/ssh-config/templates/ssh_config.tpl", {
    cluster_name         = var.cluster_name
    bastion_host         = module.aws_infrastructure.bastion_public_ip
    bastion_user         = "ubuntu"
    k8s_user             = "ubuntu"
    ssh_private_key_path = "~/.ssh/${var.ssh_key_name}.pem"
    ssh_key_name         = "~/.ssh/${var.ssh_key_name}.pem"

    controller_private_ips = module.agent_nodes.control_plane_private_ips
    worker_gpu_private_ips = module.agent_nodes.gpu_worker_private_ips
    worker_cpu_private_ips = module.agent_nodes.cpu_worker_private_ips
    nats_private_ips       = module.nats_messaging.nats_private_ips

    controllers = length(module.agent_nodes.control_plane_private_ips) > 0 ? [
      for i, ip in module.agent_nodes.control_plane_private_ips : {
        index      = i,
        private_ip = ip
      }
    ] : [],
    has_controllers = length(module.agent_nodes.control_plane_private_ips) > 0,

    worker_gpus = length(module.agent_nodes.gpu_worker_private_ips) > 0 ? [
      for i, ip in module.agent_nodes.gpu_worker_private_ips : {
        index      = i,
        private_ip = ip
      }
    ] : [],
    has_worker_gpus = length(module.agent_nodes.gpu_worker_private_ips) > 0,

    worker_cpus = length(module.agent_nodes.cpu_worker_private_ips) > 0 ? [
      for i, ip in module.agent_nodes.cpu_worker_private_ips : {
        index      = i,
        private_ip = ip
      }
    ] : [],
    has_worker_cpus = length(module.agent_nodes.cpu_worker_private_ips) > 0,

    nats_servers = length(module.nats_messaging.nats_private_ips) > 0 ? [
      for i, ip in module.nats_messaging.nats_private_ips : {
        index      = i,
        private_ip = ip
      }
    ] : [],
    has_nats_servers = length(module.nats_messaging.nats_private_ips) > 0,
  })
}