# Cloud-Agnostic Infrastructure Configuration
# This file orchestrates the deployment of self-managed Kubernetes across clouds
locals {
  common_tags = {
    Project     = "AgenticPlatform"
    Environment = var.core_config.environment
    Cluster     = var.kubernetes_config.cluster_name
    ManagedBy   = "terraform"
  }

  cluster_name = var.kubernetes_config.cluster_name
}

# Data source for Ubuntu AMI (used by spot-enabled modules)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# AWS Infrastructure (cloud-specific)
module "aws_infrastructure" {
  source = "./modules/infrastructure/cloud-specific/aws"

  core_config       = var.core_config
  network_config    = var.network_config
  nat_config        = var.nat_config
  security_config   = var.security_config
  kubernetes_config = var.kubernetes_config
}
#
# # Cloud-agnostic agent nodes deployment
# module "agent_nodes" {
#   source = "./modules/cloud-agnostic/agent-nodes"
#
#   cluster_name = coalesce(var.kubernetes_config.cluster_name, var.core_config.vpc_name)
#   cloud_provider = "aws"
#
#   cloud_config = {
#     region             = var.core_config.aws_region
#     availability_zones = module.aws_infrastructure.availability_zones_used
#     instance_profile   = module.aws_infrastructure.iam_instance_profile_name
#     security_group_ids = [
#       module.aws_infrastructure.control_plane_security_group_id,
#       module.aws_infrastructure.worker_nodes_security_group_id
#     ]
#     subnet_ids = module.aws_infrastructure.private_subnet_ids
#     vpc_id     = module.aws_infrastructure.vpc_id
#   }
#
#   ssh_key_name = var.security_config.ssh_key_name
#   kubernetes_version = var.k8s_config.k8s_major_minor_stream
#
#   control_plane_count = var.k8s_control_plane_config.on_demand_count + var.k8s_control_plane_config.spot_count
#   control_plane_instance_type = var.k8s_control_plane_config.instance_type
#
#   cpu_worker_count = var.k8s_cpu_worker_config.on_demand_count + var.k8s_cpu_worker_config.spot_count
#   cpu_worker_instance_type = var.k8s_cpu_worker_config.instance_type
#
#   gpu_worker_count = var.k8s_gpu_worker_config.on_demand_count + var.k8s_gpu_worker_config.spot_count
#   gpu_worker_instance_type = var.k8s_gpu_worker_config.instance_type
#
#   # Placeholder values - these would be generated during deployment
#   kubeadm_token = "placeholder-token"
#   certificate_key = "placeholder-cert-key"
#   control_plane_user_data = "placeholder-cp-userdata"
#   worker_user_data = "placeholder-worker-userdata"
# }
#
#   k8s_config = {
#     cluster_name                = coalesce(var.kubernetes_config.cluster_name, var.core_config.vpc_name)
#     control_plane_instance_type = var.k8s_control_plane_config.instance_type
#     controller_on_demand_count  = var.k8s_control_plane_config.on_demand_count
#     controller_spot_count       = var.k8s_control_plane_config.spot_count
#     ssh_public_key_path         = var.k8s_config.ssh_public_key_path
#     k8s_user                    = var.k8s_config.k8s_user
#     k8s_major_minor_stream      = var.k8s_config.k8s_major_minor_stream
#     k8s_full_patch_version      = var.k8s_config.k8s_full_patch_version
#     k8s_apt_package_suffix      = var.k8s_config.k8s_apt_package_suffix
#     spot_instance_types         = var.k8s_control_plane_config.spot_instance_types
#   }
# }

