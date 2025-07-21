# modules/iam/main.tf
# IAM resources for Kubernetes cluster

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Local values for computed configurations
locals {
  # Use provided role names or generate defaults
  control_plane_role_name = var.control_plane_role_name != null ? var.control_plane_role_name : "${var.project}-control-plane-role"
  worker_role_name        = var.worker_role_name != null ? var.worker_role_name : "${var.project}-worker-role"
  gpu_worker_role_name    = var.gpu_worker_role_name != null ? var.gpu_worker_role_name : "${var.project}-gpu-worker-role"
  cluster_name            = var.cluster_name != null ? var.cluster_name : var.project

  # Common tags
  common_tags = merge({
    Project   = var.project
    ManagedBy = "terraform"
    Module    = "iam"
  }, var.tags)
}

# Data source for EC2 service
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Data source for Spot Fleet service
data "aws_iam_policy_document" "spot_fleet_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["spotfleet.amazonaws.com"]
    }
  }
}

#===============================================================================
# General EC2 Role (used as base for all instances)
#===============================================================================

resource "aws_iam_role" "ec2_role" {
  name               = "${var.project}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.project}-ec2-role"
    Type = "ec2-base"
  })
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "${var.project}-ec2-instance-profile"
  role = aws_iam_role.ec2_role.name

  tags = local.common_tags
}

# Basic EC2 permissions
resource "aws_iam_role_policy_attachment" "ec2_ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_cloudwatch_agent" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

#===============================================================================
# Control Plane Role
#===============================================================================

resource "aws_iam_role" "control_plane_role" {
  name               = local.control_plane_role_name
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = merge(local.common_tags, {
    Name = local.control_plane_role_name
    Type = "kubernetes-control-plane"
  })
}

resource "aws_iam_instance_profile" "control_plane_instance_profile" {
  name = "${local.control_plane_role_name}-instance-profile"
  role = aws_iam_role.control_plane_role.name

  tags = local.common_tags
}

# Control plane specific permissions
data "aws_iam_policy_document" "control_plane_policy" {
  # EC2 permissions for managing instances and networking
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVolumes",
      "ec2:CreateSecurityGroup",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifyVolume",
      "ec2:AttachVolume",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteVolume",
      "ec2:DetachVolume",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:DescribeVpcs",
      "elasticloadbalancing:*"
    ]
    resources = ["*"]
  }

  # S3 permissions for bootstrap and backups
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::${var.project}-*",
      "arn:aws:s3:::${var.project}-*/*"
    ]
  }

  # Auto Scaling permissions
  statement {
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "ec2:DescribeLaunchTemplateVersions"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "control_plane_policy" {
  name   = "${local.control_plane_role_name}-policy"
  policy = data.aws_iam_policy_document.control_plane_policy.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "control_plane_policy_attachment" {
  role       = aws_iam_role.control_plane_role.name
  policy_arn = aws_iam_policy.control_plane_policy.arn
}

# Attach base EC2 policies
resource "aws_iam_role_policy_attachment" "control_plane_ssm" {
  role       = aws_iam_role.control_plane_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "control_plane_cloudwatch" {
  role       = aws_iam_role.control_plane_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

#===============================================================================
# Worker Node Role
#===============================================================================

resource "aws_iam_role" "worker_role" {
  name               = local.worker_role_name
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = merge(local.common_tags, {
    Name = local.worker_role_name
    Type = "kubernetes-worker"
  })
}

resource "aws_iam_instance_profile" "worker_instance_profile" {
  name = "${local.worker_role_name}-instance-profile"
  role = aws_iam_role.worker_role.name

  tags = local.common_tags
}

# Worker node specific permissions
data "aws_iam_policy_document" "worker_policy" {
  # EC2 permissions for basic operations
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVolumes",
      "ec2:CreateTags"
    ]
    resources = ["*"]
  }

  # S3 permissions for bootstrap scripts
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::${var.project}-*",
      "arn:aws:s3:::${var.project}-*/*"
    ]
  }

  # ECR permissions for pulling images
  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:BatchGetImage",
      "ecr:GetAuthorizationToken"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "worker_policy" {
  name   = "${local.worker_role_name}-policy"
  policy = data.aws_iam_policy_document.worker_policy.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "worker_policy_attachment" {
  role       = aws_iam_role.worker_role.name
  policy_arn = aws_iam_policy.worker_policy.arn
}

# Attach base EC2 policies
resource "aws_iam_role_policy_attachment" "worker_ssm" {
  role       = aws_iam_role.worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "worker_cloudwatch" {
  role       = aws_iam_role.worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

#===============================================================================
# GPU Worker Role (separate role with additional permissions)
#===============================================================================

resource "aws_iam_role" "gpu_worker_role" {
  name               = local.gpu_worker_role_name
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = merge(local.common_tags, {
    Name = local.gpu_worker_role_name
    Type = "kubernetes-gpu-worker"
  })
}

resource "aws_iam_instance_profile" "gpu_worker_instance_profile" {
  name = "${local.gpu_worker_role_name}-instance-profile"
  role = aws_iam_role.gpu_worker_role.name

  tags = local.common_tags
}

# GPU worker inherits all worker permissions plus additional GPU-specific permissions
data "aws_iam_policy_document" "gpu_worker_policy" {
  # Include all worker permissions
  source_policy_documents = [data.aws_iam_policy_document.worker_policy.json]

  # Additional GPU-specific permissions
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeSpotInstanceRequests",
      "ec2:DescribeSpotPriceHistory"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "gpu_worker_policy" {
  name   = "${local.gpu_worker_role_name}-policy"
  policy = data.aws_iam_policy_document.gpu_worker_policy.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "gpu_worker_policy_attachment" {
  role       = aws_iam_role.gpu_worker_role.name
  policy_arn = aws_iam_policy.gpu_worker_policy.arn
}

# Attach base EC2 policies
resource "aws_iam_role_policy_attachment" "gpu_worker_ssm" {
  role       = aws_iam_role.gpu_worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "gpu_worker_cloudwatch" {
  role       = aws_iam_role.gpu_worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

#===============================================================================
# Spot Fleet Role
#===============================================================================

resource "aws_iam_role" "spot_fleet_role" {
  name               = "${var.project}-spot-fleet-role"
  assume_role_policy = data.aws_iam_policy_document.spot_fleet_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.project}-spot-fleet-role"
    Type = "spot-fleet"
  })
}

resource "aws_iam_role_policy_attachment" "spot_fleet_policy" {
  role       = aws_iam_role.spot_fleet_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2SpotFleetTaggingRole"
}

#===============================================================================
# EC2 Instance Connect Policy
#===============================================================================

data "aws_iam_policy_document" "ec2_instance_connect" {
  statement {
    effect = "Allow"
    actions = [
      "ec2-instance-connect:SendSSHPublicKey"
    ]
    resources = [
      "arn:aws:ec2:${var.aws_region}:${var.account_id}:instance/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "ec2:osuser"
      values   = ["ubuntu", "ec2-user"]
    }
  }
}

resource "aws_iam_policy" "ec2_instance_connect" {
  name   = "${var.project}-ec2-instance-connect"
  policy = data.aws_iam_policy_document.ec2_instance_connect.json

  tags = local.common_tags
}
