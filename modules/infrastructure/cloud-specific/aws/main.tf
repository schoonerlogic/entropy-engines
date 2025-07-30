# Extract values from individual variables for easier access
locals {
  # Core values
  aws_region  = var.aws_region
  project     = var.project
  environment = var.environment
  vpc_name    = var.vpc_name

  # Security values
  ssh_key_name = var.ssh_key_name

  # NAT configuration
  nat_type = var.nat_type

  # Determine bastion type from security config
  bastion_type = var.enable_bastion_host ? var.bastion_instance_type : "none"

  k8s_scripts_bucket_name = "k8s-scripts-bucket-${random_id.bucket_suffix.hex}"
}

provider "aws" {
  region = local.aws_region
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "k8s_scripts_bucket" {
  bucket        = local.k8s_scripts_bucket_name
  force_destroy = true # This allows non-empty buckets to be destroyed

  # Enable versioning for safety
  tags = {
    Name        = local.k8s_scripts_bucket_name
    Environment = local.environment
  }
}

resource "aws_s3_bucket_versioning" "k8s_scripts" {
  bucket = aws_s3_bucket.k8s_scripts_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "k8s_scripts_bucket_ownership" {
  bucket = aws_s3_bucket.k8s_scripts_bucket.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Bucket readiness verification
resource "null_resource" "bucket_ready" {
  triggers = {
    bucket_name = aws_s3_bucket.k8s_scripts_bucket.bucket
  }

  # Explicit dependency chain
  depends_on = [
    aws_s3_bucket.k8s_scripts_bucket,
    aws_s3_bucket_versioning.k8s_scripts,
    aws_s3_bucket_ownership_controls.k8s_scripts_bucket_ownership
  ]

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      end_time=$(( $(date +%s) + 300 )) # 5 minute timeout

      while [ $(date +%s) -lt $end_time ]; do
        if aws s3api head-bucket --bucket ${aws_s3_bucket.k8s_scripts_bucket.bucket} >/dev/null 2>&1; then
          echo "Bucket is ready"
          exit 0
        fi
        echo "Waiting for bucket to become ready..."
        sleep 5
      done
      echo "Timeout waiting for bucket ${aws_s3_bucket.k8s_scripts_bucket.bucket}"
      exit 1
    EOT
  }
}

# Pass individual variables to submodules
module "network" {
  source = "./modules/network"

  # Core values
  project      = local.project
  vpc_name     = local.vpc_name
  region       = local.aws_region
  environment  = local.environment
  base_aws_ami = var.base_aws_ami

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
  k8s_scripts_bucket_name = local.k8s_scripts_bucket_name
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
