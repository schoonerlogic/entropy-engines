# root - kubernetes.tf
# Controllers Module - No Provisioners, Self-Bootstrapping

# Get current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  # Create core_config from your existing variables
  merged_core_config = {
    aws_region  = data.aws_region.current.name
    environment = var.core_config.environment
    project     = var.core_config.project
    vpc_name    = var.core_config.vpc_name
  }
}

module "kubernetes" {
  source = "./modules/kubernetes"

  # Core configuration
  core_config = local.merged_core_config

  # AMIi
  aws_ami = data.aws_ami.ubuntu.id

  # AWS region (as object since module expects this)
  aws_region = data.aws_region.current

  # S3 bucket name
  k8s_scripts_bucket_name = module.aws_infrastructure.k8s_scripts_bucket_name

  # All the configuration objects
  kubernetes_config        = var.kubernetes_config
  network_config           = var.network_config
  instance_config          = var.instance_config
  iam_config               = var.iam_config
  k8s_control_plane_config = var.k8s_control_plane_config
  worker_config            = var.worker_config

  # Additional required variables that were missing
  security_config = var.security_config

  # Network variables (these need to be extracted from your network_config or passed separately)
  pod_cidr_block     = module.aws_infrastructure.pod_cidr_block
  service_cidr_block = module.aws_infrastructure.service_cidr_block
  subnet_ids         = module.aws_infrastructure.private_subnet_ids
  security_group_ids = [module.aws_infrastructure.control_plane_security_group_id]

  # Role names (these can be extracted from iam_config or passed separately)
  control_plane_role_name = var.control_plane_role_name
  worker_role_name        = var.worker_role_name
  gpu_worker_role_name    = var.gpu_worker_role_name

  depends_on = [module.aws_infrastructure]
}

module "ssh_config" {
  source = "./modules/ssh-config"

  cluster_name         = var.kubernetes_config.cluster_name
  bastion_host         = module.aws_infrastructure.bastion_public_ip
  bastion_user         = var.security_config.bastion_user
  k8s_user             = var.kubernetes_config.k8s_user
  ssh_private_key_path = var.security_config.ssh_private_key_path

  controller_private_ips = module.kubernetes.controller_instance_private_ips
  worker_gpu_private_ips = length(module.kubernetes.gpu_instance_private_ips) > 0 ? module.kubernetes.gpu_instance_private_ips[0] : []
  worker_cpu_private_ips = length(module.kubernetes.cpu_instance_private_ips) > 0 ? module.kubernetes.cpu_instance_private_ips[0] : []
}
