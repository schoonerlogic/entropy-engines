# Cloud-Agnostic Agent Nodes Module
# This module creates CPU and GPU worker nodes for the Kubernetes cluster

# Local values for cloud-specific configurations
locals {
  common_tags = {
    Cluster     = var.cluster_name
    Environment = "dev"
    ManagedBy   = "terraform"
  }

  # Cloud-specific instance configurations
  instance_configs = {
    aws = {
      ami_filter = {
        owners      = ["099720109477"] # Canonical
        name_filter = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-*-server-*"
      }
      user_data_template = "${path.module}/templates/aws-user-data.sh.tftpl"
    }
    gcp = {
      image_family       = "ubuntu-2204-lts"
      image_project      = "ubuntu-os-cloud"
      user_data_template = "${path.module}/templates/gcp-user-data.sh.tftpl"
    }
    azure = {
      image_publisher    = "Canonical"
      image_offer        = "0001-com-ubuntu-server-jammy"
      image_sku          = "22_04-lts-gen2"
      user_data_template = "${path.module}/templates/azure-user-data.sh.tftpl"
    }
  }

  instance_config = local.instance_configs[var.cloud_provider]
}

# AWS-specific resources
resource "aws_instance" "control_plane" {
  count = var.cloud_provider == "aws" ? var.control_plane_count : 0

  ami                    = data.aws_ami.ubuntu[0].id
  instance_type          = var.control_plane_instance_type
  key_name               = var.ssh_key_name
  subnet_id              = var.cloud_config.subnet_ids[count.index % length(var.cloud_config.subnet_ids)]
  vpc_security_group_ids = var.cloud_config.security_group_ids
  iam_instance_profile   = var.cloud_config.instance_profile

  user_data = var.control_plane_user_data

  tags = merge(local.common_tags, {
    Name     = "${var.cluster_name}-control-plane-${count.index + 1}"
    NodeType = "control-plane"
    Role     = "master"
  })

  root_block_device {
    volume_type = "gp3"
    volume_size = 50
    encrypted   = true
  }
}

resource "aws_instance" "cpu_worker" {
  count = var.cloud_provider == "aws" ? var.cpu_worker_count : 0

  ami                    = data.aws_ami.ubuntu[0].id
  instance_type          = var.cpu_worker_instance_type
  key_name               = var.ssh_key_name
  subnet_id              = var.cloud_config.subnet_ids[count.index % length(var.cloud_config.subnet_ids)]
  vpc_security_group_ids = var.cloud_config.security_group_ids
  iam_instance_profile   = var.cloud_config.instance_profile

  user_data = var.worker_user_data

  tags = merge(local.common_tags, {
    Name      = "${var.cluster_name}-cpu-worker-${count.index + 1}"
    NodeType  = "worker"
    AgentType = "cpu"
  })

  root_block_device {
    volume_type = "gp3"
    volume_size = 100
    encrypted   = true
  }
}

resource "aws_instance" "gpu_worker" {
  count = var.cloud_provider == "aws" ? var.gpu_worker_count : 0

  ami                    = data.aws_ami.ubuntu[0].id
  instance_type          = var.gpu_worker_instance_type
  key_name               = var.ssh_key_name
  subnet_id              = var.cloud_config.subnet_ids[count.index % length(var.cloud_config.subnet_ids)]
  vpc_security_group_ids = var.cloud_config.security_group_ids
  iam_instance_profile   = var.cloud_config.instance_profile

  user_data = var.worker_user_data

  tags = merge(local.common_tags, {
    Name      = "${var.cluster_name}-gpu-worker-${count.index + 1}"
    NodeType  = "worker"
    AgentType = "gpu"
  })

  root_block_device {
    volume_type = "gp3"
    volume_size = 200
    encrypted   = true
  }
}

# Data source for Ubuntu AMI
data "aws_ami" "ubuntu" {
  count = var.cloud_provider == "aws" ? 1 : 0

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