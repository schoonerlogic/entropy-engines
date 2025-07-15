# Enhanced IAM Module for Cloud-Agnostic Kubernetes
# Includes cloud-controller-manager roles and security best practices

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Base EC2 Role for Kubernetes nodes
resource "aws_iam_role" "ec2_role" {
  name = "${var.project}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project}-ec2-role"
    Environment = var.environment
    Project     = var.project
  }
}

# Cloud Controller Manager Role
resource "aws_iam_role" "cloud_controller_manager_role" {
  name = "${var.project}-cloud-controller-manager"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "ec2:InstanceProfile" = aws_iam_instance_profile.control_plane_profile.arn
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project}-cloud-controller-manager"
    Environment = var.environment
    Project     = var.project
    Component   = "kubernetes"
  }
}

# Cloud Controller Manager Policy
resource "aws_iam_policy" "cloud_controller_manager_policy" {
  name        = "${var.project}-cloud-controller-manager-policy"
  description = "Policy for AWS Cloud Controller Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeTags",
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
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:AttachLoadBalancerToSubnets",
          "elasticloadbalancing:ApplySecurityGroupsToLoadBalancer",
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateLoadBalancerPolicy",
          "elasticloadbalancing:CreateLoadBalancerListeners",
          "elasticloadbalancing:ConfigureHealthCheck",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DeleteLoadBalancerListeners",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DetachLoadBalancerFromSubnets",
          "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
          "elasticloadbalancing:SetLoadBalancerPoliciesForBackendServer",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeLoadBalancerPolicies",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:SetLoadBalancerPoliciesOfListener",
          "iam:CreateServiceLinkedRole",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

# Control Plane Role (for masters)
resource "aws_iam_role" "control_plane_role" {
  name = "${var.project}-control-plane-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project}-control-plane-role"
    Environment = var.environment
    Project     = var.project
    Component   = "kubernetes"
    NodeType    = "control-plane"
  }
}

# Worker Node Role
resource "aws_iam_role" "worker_role" {
  name = "${var.project}-worker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project}-worker-role"
    Environment = var.environment
    Project     = var.project
    Component   = "kubernetes"
    NodeType    = "worker"
  }
}

# GPU Node Role (extends worker role)
resource "aws_iam_role" "gpu_worker_role" {
  name = "${var.project}-gpu-worker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project}-gpu-worker-role"
    Environment = var.environment
    Project     = var.project
    Component   = "kubernetes"
    NodeType    = "gpu-worker"
  }
}

# Base Kubernetes Node Policy
resource "aws_iam_policy" "kubernetes_node_policy" {
  name        = "${var.project}-kubernetes-node-policy"
  description = "Base policy for Kubernetes nodes"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVolumes",
          "ec2:DescribeVpcs",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:DeleteVolume",
          "ec2:ModifyVolume",
          "ec2:DescribeVolumesModifications",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeLoadBalancerPolicies",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

# GPU-specific policy
resource "aws_iam_policy" "gpu_node_policy" {
  name        = "${var.project}-gpu-node-policy"
  description = "Additional policy for GPU nodes"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstances",
          "ec2:DescribeImages"
        ]
        Resource = "*"
      }
    ]
  })
}

# Enhanced EC2 Instance Connect Policy
resource "aws_iam_policy" "ec2_instance_connect" {
  name        = "${var.project}-ec2-connect"
  description = "Policy for EC2 Instance Connect"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2-instance-connect:SendSSHPublicKey",
          "ec2-instance-connect:SendSerialConsoleSSHPublicKey"
        ]
        Resource = [
          "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# SSM Policy for Systems Manager
resource "aws_iam_policy" "ssm_policy" {
  name        = "${var.project}-ssm-policy"
  description = "Policy for SSM access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:DescribeAssociation",
          "ssm:GetDeployablePatchSnapshotForInstance",
          "ssm:GetDocument",
          "ssm:GetManifest",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:ListAssociations",
          "ssm:ListInstanceAssociations",
          "ssm:PutInventory",
          "ssm:PutComplianceItems",
          "ssm:PutConfigurePackageResult",
          "ssm:UpdateAssociationStatus",
          "ssm:UpdateInstanceAssociationStatus",
          "ssm:UpdateInstanceInformation"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

# Instance Profiles
resource "aws_iam_instance_profile" "control_plane_profile" {
  name = "${var.project}-control-plane-profile"
  role = aws_iam_role.control_plane_role.name

  tags = {
    Name        = "${var.project}-control-plane-profile"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_instance_profile" "worker_profile" {
  name = "${var.project}-worker-profile"
  role = aws_iam_role.worker_role.name

  tags = {
    Name        = "${var.project}-worker-profile"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_instance_profile" "gpu_worker_profile" {
  name = "${var.project}-gpu-worker-profile"
  role = aws_iam_role.gpu_worker_role.name

  tags = {
    Name        = "${var.project}-gpu-worker-profile"
    Environment = var.environment
    Project     = var.project
  }
}

# Base EC2 Profile (legacy compatibility)
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project}-ec2-profile"
  role = aws_iam_role.ec2_role.name

  tags = {
    Name        = "${var.project}-ec2-profile"
    Environment = var.environment
    Project     = var.project
  }
}

# Spot Fleet Role
resource "aws_iam_role" "spot_fleet_role" {
  name = "${var.project}-spot-fleet-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "spotfleet.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project}-spot-fleet-role"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_role_policy_attachment" "spot_fleet_role_policy_attach" {
  role       = aws_iam_role.spot_fleet_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2SpotFleetTaggingRole"
}

# Policy Attachments
resource "aws_iam_role_policy_attachment" "control_plane_kubernetes" {
  role       = aws_iam_role.control_plane_role.name
  policy_arn = aws_iam_policy.kubernetes_node_policy.arn
}

resource "aws_iam_role_policy_attachment" "control_plane_ccm" {
  role       = aws_iam_role.cloud_controller_manager_role.name
  policy_arn = aws_iam_policy.cloud_controller_manager_policy.arn
}

resource "aws_iam_role_policy_attachment" "control_plane_ssm" {
  role       = aws_iam_role.control_plane_role.name
  policy_arn = aws_iam_policy.ssm_policy.arn
}

resource "aws_iam_role_policy_attachment" "control_plane_connect" {
  role       = aws_iam_role.control_plane_role.name
  policy_arn = aws_iam_policy.ec2_instance_connect.arn
}

resource "aws_iam_role_policy_attachment" "worker_kubernetes" {
  role       = aws_iam_role.worker_role.name
  policy_arn = aws_iam_policy.kubernetes_node_policy.arn
}

resource "aws_iam_role_policy_attachment" "worker_ssm" {
  role       = aws_iam_role.worker_role.name
  policy_arn = aws_iam_policy.ssm_policy.arn
}

resource "aws_iam_role_policy_attachment" "worker_connect" {
  role       = aws_iam_role.worker_role.name
  policy_arn = aws_iam_policy.ec2_instance_connect.arn
}

resource "aws_iam_role_policy_attachment" "worker_ebs_csi" {
  role       = aws_iam_role.worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_iam_role_policy_attachment" "worker_ecr_read" {
  role       = aws_iam_role.worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "gpu_worker_kubernetes" {
  role       = aws_iam_role.gpu_worker_role.name
  policy_arn = aws_iam_policy.kubernetes_node_policy.arn
}

resource "aws_iam_role_policy_attachment" "gpu_worker_gpu" {
  role       = aws_iam_role.gpu_worker_role.name
  policy_arn = aws_iam_policy.gpu_node_policy.arn
}

resource "aws_iam_role_policy_attachment" "gpu_worker_ssm" {
  role       = aws_iam_role.gpu_worker_role.name
  policy_arn = aws_iam_policy.ssm_policy.arn
}

resource "aws_iam_role_policy_attachment" "gpu_worker_connect" {
  role       = aws_iam_role.gpu_worker_role.name
  policy_arn = aws_iam_policy.ec2_instance_connect.arn
}

resource "aws_iam_role_policy_attachment" "gpu_worker_ebs_csi" {
  role       = aws_iam_role.gpu_worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_iam_role_policy_attachment" "gpu_worker_ecr_read" {
  role       = aws_iam_role.gpu_worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Legacy attachments for backward compatibility
resource "aws_iam_role_policy_attachment" "ec2_kubernetes" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.kubernetes_node_policy.arn
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ssm_policy.arn
}

resource "aws_iam_role_policy_attachment" "ec2_connect" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_instance_connect.arn
}

resource "aws_iam_role_policy_attachment" "ec2_ebs_csi" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_iam_role_policy_attachment" "ec2_ecr_read" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}