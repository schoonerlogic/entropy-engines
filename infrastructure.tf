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

module "kubernetes-cluster" {
  source                    = "./modules/cloud-agnostic/kubernetes-cluster"
  ssh_key_name              = var.ssh_key_name
  subnet_ids                = module.aws_infrastructure.private_subnet_ids
  security_group_ids        = [module.aws_infrastructure.control_plane_security_group_id]
  iam_instance_profile_name = module.aws_infrastructure.iam_instance_profile_name
  cloud_provider            = "aws"
  cluster_name              = var.cluster_name
  control_plane_private_ips = module.controllers.private_ips
  cloud_config              = local.cloud_config
}

module "shared-aws-vpc" {
  source = "./modules/shared-aws-vpc"

  # Core settings - only vpc_name is required
  core_config = {
    vpc_name    = "my-vpc"
    environment = "prod"      # Override default
    aws_region  = "us-west-2" # Override default
    # project uses default "agentic-platform"
  }

  # Security settings - only ssh_key_name is required
  security_config = {
    ssh_key_name      = "my-key-pair"
    ssh_allowed_cidrs = ["10.0.0.0/8", "172.16.0.0/12"]
    # All other security settings use defaults
  }

  # Network settings - all optional, uses defaults if not specified
  network_config = {
    vpc_cidr = "172.16.0.0/16" # Override default
    # Everything else uses defaults
  }

  # All other config objects are optional and use defaults
  # nat_config, kubernetes_config, instance_config, cost_optimization all use defaults
}

# Spot-enabled worker nodes and controllers
module "controllers" {
  source = "./modules/controllers"

  instance_count              = var.control_plane_count
  aws_region                  = var.aws_region
  project                     = var.project
  cluster_name                = var.cluster_name
  base_ami_id                 = data.aws_ami.ubuntu.id
  pod_cidr_block              = module.shared-aws-vpc.pod_cidr_block
  service_cidr_block          = module.shared-aws-vpc.service_cidr_block
  controller_role_name        = module.shared-aws-vpc.ec2_role_name
  instance_type               = var.control_plane_instance_type
  controller_on_demand_count  = 0
  controller_spot_count       = var.control_plane_count
  subnet_ids                  = module.aws_infrastructure.private_subnet_ids
  security_group_ids          = [module.aws_infrastructure.control_plane_security_group_id]
  ssh_key_name                = var.ssh_key_name
  ssh_private_key_path        = "~/.ssh/${var.ssh_key_name}.pem"
  ssh_public_key_path         = "~/.ssh/${var.ssh_key_name}.pem.pub"
  k8s_user                    = "ubuntu"
  k8s_major_minor_stream      = var.kubernetes_version
  k8s_full_patch_version      = var.kubernetes_version
  k8s_apt_package_suffix      = "-00"
  spot_instance_types         = [var.cpu_worker_instance_type]
  iam_policy_version          = "v1"
  bastion_host                = module.aws_infrastructure.bastion_public_ip
  bastion_user                = "ubuntu"
  associate_public_ip_address = "false"
}

module "worker_cpus" {
  source = "./modules/worker-cpus"
  count  = var.cpu_worker_count > 0 ? 1 : 0

  worker_s3_bootstrap_bucket  = aws_s3_bucket.worker_s3_bootstrap_bucket
  worker_cpu_bootstrap_script = aws_s3_object.worker_cpu_bootstrap_script

  base_ami_id  = data.aws_ami.ubuntu.id
  use_base_ami = var.use_base_ami

  # Nodes
  instance_count            = var.cpu_worker_count
  instance_type             = var.cpu_worker_instance_type
  spot_instance_types       = [var.cpu_worker_instance_type]
  spot_fleet_iam_role_arn   = module.shared-aws-vpc.spot_fleet_role_arn
  iam_instance_profile_name = module.aws_infrastructure.iam_instance_profile_name
  iam_policy_version        = "v1"
  ssm_join_command_path     = "/entropy-engines/kubeadm-join-command"

  # Cluster inetworko
  cluster_name           = var.cluster_name
  k8s_user               = "ubuntu"
  k8s_major_minor_stream = var.kubernetes_version

  # VPC
  bastion_host                = module.aws_infrastructure.bastion_public_ip
  bastion_user                = var.bastion_user
  cluster_dns_ip              = cidrhost(var.pod_cidr, 10)
  associate_public_ip_address = "false"
  subnet_ids                  = module.aws_infrastructure.private_subnet_ids

  # Security
  security_group_ids   = [module.aws_infrastructure.worker_nodes_security_group_id]
  ssh_key_name         = var.ssh_key_name
  ssh_private_key_path = "~/.ssh/${var.ssh_key_name}.pem"
  ssh_public_key_path  = "~/.ssh/${var.ssh_key_name}.pem.pub"

  depends_on = [module.controllers]
}


module "worker_gpus" {
  source = "./modules/worker-gpus"
  count  = var.gpu_worker_count > 0 ? 1 : 0

  instance_count              = var.gpu_worker_count
  cluster_name                = var.cluster_name
  base_ami_id                 = data.aws_ami.ubuntu.id
  use_base_ami                = var.use_base_ami
  instance_type               = var.gpu_worker_instance_type
  gpu_on_demand_count         = 0
  gpu_spot_count              = var.gpu_worker_count
  subnet_ids                  = module.aws_infrastructure.private_subnet_ids
  security_group_ids          = [module.aws_infrastructure.worker_nodes_security_group_id]
  ssh_key_name                = var.ssh_key_name
  ssh_private_key_path        = "~/.ssh/${var.ssh_key_name}.pem"
  ssh_public_key_path         = "~/.ssh/${var.ssh_key_name}.pem.pub"
  k8s_user                    = "ubuntu"
  k8s_major_minor_stream      = var.kubernetes_version
  k8s_full_patch_version      = var.kubernetes_version
  k8s_apt_package_suffix      = "-00"
  s3_bucket_region            = var.aws_region
  cluster_dns_ip              = cidrhost(var.pod_cidr, 10)
  ssm_join_command_path       = "/entropy-engines/kubeadm-join-command"
  iam_instance_profile_name   = module.aws_infrastructure.iam_instance_profile_name
  spot_fleet_iam_role_arn     = module.shared-aws-vpc.spot_fleet_role_arn
  spot_instance_types         = [var.gpu_worker_instance_type]
  worker_s3_bootstrap_bucket  = { id = aws_s3_bucket.worker_s3_bootstrap_bucket.id }
  worker_gpu_bootstrap_script = [{ key = "gpu-node-init.sh" }]
  iam_policy_version          = "v1"
  bastion_host                = module.aws_infrastructure.bastion_public_ip
  bastion_user                = var.bastion_user
  associate_public_ip_address = "false"

  depends_on = [module.controllers]
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

    controller_private_ips = var.control_plane_count > 0 ? module.controllers.private_ips : []
    worker_cpu_private_ips = var.cpu_worker_count > 0 && length(module.worker_cpus) > 0 ? module.worker_cpus[0].private_ips : []
    worker_cpu_private_ips = var.gpu_worker_count > 0 && length(module.worker_gpus) > 0 ? module.worker_gpus[0].private_ips : []

    nats_private_ips = module.nats_messaging.nats_private_ips

    controllers = var.control_plane_count > 0 ? [
      for i, ip in module.controllers.private_ips : {
        index      = i,
        private_ip = ip
      }
    ] : [],
    has_controllers = var.control_plane_count > 0,

    worker_cpus = var.cpu_worker_count > 0 && length(module.worker_cpus) > 0 ? [
      for i, ip in module.worker_cpus[0].private_ips : {
        index      = i,
        private_ip = ip
      }
    ] : [],
    has_worker_cpus = var.cpu_worker_count > 0 && length(module.worker_cpus) > 0,

    worker_gpus = var.gpu_worker_count > 0 && length(module.worker_gpus) > 0 ? [
      for i, ip in module.worker_gpus[0].private_ips : {
        index      = i,
        private_ip = ip
      }
    ] : [],
    has_worker_gpus = var.gpu_worker_count > 0 && length(module.worker_gpus) > 0,

    nats_servers = length(module.nats_messaging.nats_private_ips) > 0 ? [
      for i, ip in module.nats_messaging.nats_private_ips : {
        index      = i,
        private_ip = ip
      }
    ] : [],
    has_nats_servers = length(module.nats_messaging.nats_private_ips) > 0,
  })
}


# --- S3 Bucket Creation ---

data "aws_caller_identity" "current" {
  # This data source requires no configuration arguments.
}

resource "aws_s3_bucket" "worker_s3_bootstrap_bucket" {
  bucket = "${var.cluster_name}-${var.environment}-bootstrap-scripts-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_object" "worker_cpu_bootstrap_script" {
  count = (var.cpu_worker_count) > 0 ? 1 : 0

  bucket = aws_s3_bucket.worker_s3_bootstrap_bucket.id
  # Use a hash of the script content in the key name.
  # This means if the script changes, the key changes, ensuring updates.
  key    = "modules/worker-cpus/scripts/cpu-node-init-${sha1(file("modules/worker-cpus/scripts/cpu-node-init.sh"))}.sh"
  source = "modules/worker-cpus/scripts/cpu-node-init.sh" # Path to your existing LARGE script

  # Ensure Terraform replaces the object if the file content changes
  etag = filemd5("modules/worker-cpus/scripts/cpu-node-init.sh")

  # Optional: Set content type for clarity
  content_type = "text/x-shellscript"

  tags = {
    Name        = "k8s-worker-bootstrap-scripts"
    Script      = "cpu-node-init.sh"
    Environment = var.environment
  }
}

resource "aws_s3_object" "worker_gpu_bootstrap_script" {
  count = (var.gpu_worker_count) > 0 ? 1 : 0

  bucket = aws_s3_bucket.worker_s3_bootstrap_bucket.id
  # Use a hash of the script content in the key name.
  # This means if the script changes, the key changes, ensuring updates.
  key    = "modules/worker-gpus/scripts/gpu-node-init-${sha1(file("modules/worker-gpus/scripts/gpu-node-init.sh"))}.sh"
  source = "modules/worker-gpus/scripts/gpu-node-init.sh" # Path to your existing LARGE script

  # Ensure Terraform replaces the object if the file content changes
  etag = filemd5("modules/worker-gpus/scripts/gpu-node-init.sh")

  # Optional: Set content type for clarity
  content_type = "text/x-shellscript"

  tags = {
    Name        = "k8s-worker-bootstrap-scripts"
    Script      = "gpu-node-init.sh"
    Environment = var.environment
  }
}

