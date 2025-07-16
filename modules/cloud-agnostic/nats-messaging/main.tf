# Cloud-Agnostic NATS Messaging Module
# This module sets up NATS messaging infrastructure for inter-agent communication

# Local values
locals {
  common_tags = {
    Cluster     = var.cluster_name
    Environment = "dev"
    ManagedBy   = "terraform"
    Service     = "nats"
  }

  nats_config = templatefile("${path.module}/templates/nats-server.conf.tftpl", {
    cluster_name = var.cluster_name
    cluster_size = var.nats_cluster_size
  })

  nats_user_data = base64encode(templatefile("${path.module}/templates/nats-setup.sh.tftpl", {
    nats_version = var.nats_version
    nats_config  = local.nats_config
    ARCH         = "arm64" # Default for ARM64 instances
  }))
}

# AWS NATS instances
resource "aws_instance" "nats" {
  count = var.cloud_provider == "aws" ? var.nats_cluster_size : 0

  ami                    = data.aws_ami.ubuntu[0].id
  instance_type          = var.nats_instance_type
  subnet_id              = var.cloud_config.subnet_ids[count.index % length(var.cloud_config.subnet_ids)]
  vpc_security_group_ids = var.cloud_config.security_group_ids
  iam_instance_profile   = var.cloud_config.instance_profile

  user_data = local.nats_user_data

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-nats-${count.index + 1}"
  })

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
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

# Security group for NATS (if not using shared security groups)
resource "aws_security_group" "nats" {
  count = var.cloud_provider == "aws" ? 1 : 0

  name        = "${var.cluster_name}-nats"
  description = "Security group for NATS messaging"
  vpc_id      = var.cloud_config.vpc_id

  # NATS client port
  ingress {
    from_port   = 4222
    to_port     = 4222
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  # NATS monitoring port
  ingress {
    from_port   = 8222
    to_port     = 8222
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  # NATS cluster routing port
  ingress {
    from_port = 6222
    to_port   = 6222
    protocol  = "tcp"
    self      = true
  }

  # NATS leafnode port
  ingress {
    from_port   = 7422
    to_port     = 7422
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-nats"
  })
}