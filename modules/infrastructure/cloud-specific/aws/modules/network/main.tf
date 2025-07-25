# modules/network/main.tf
# Enhanced AWS VPC Module for Cloud-Agnostic Kubernetes
# Updated to use individual variables instead of config objects

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Use provided availability zones or discover available ones
  azs = var.availability_zones != null ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, max(var.public_subnet_count, var.private_subnet_count))

  # Use individual variables for network configuration
  vpc_cidr_block     = var.vpc_cidr
  pod_cidr_block     = var.kubernetes_cidrs.pod_cidr
  service_cidr_block = var.kubernetes_cidrs.service_cidr
  cluster_dns_ip     = cidrhost(var.kubernetes_cidrs.service_cidr, 10)

  # Dynamic subnet calculation
  public_subnet_cidrs  = [for i in range(var.public_subnet_count) : cidrsubnet(local.vpc_cidr_block, 8, i)]
  private_subnet_cidrs = [for i in range(var.private_subnet_count) : cidrsubnet(local.vpc_cidr_block, 8, i + 100)]

  # Kubernetes cluster name for tagging
  cluster_name = var.kubernetes_cluster_name != null ? var.kubernetes_cluster_name : var.project

  # Common tags with enhanced metadata
  common_tags = merge({
    Environment                                   = var.environment
    Project                                       = var.project
    ClusterName                                   = local.cluster_name
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
    ManagedBy                                     = "Terraform"
    }, var.enable_kubernetes_tags ? {
    "kubernetes.io/role/elb"          = "1"
    "kubernetes.io/role/internal-elb" = "1"
  } : {})

  # Security group names
  control_plane_sg_name = "${var.project}-control-plane-${var.environment}-sg"
  nodes_sg_name         = "${var.project}-nodes-${var.environment}-sg"
  gpu_nodes_sg_name     = "${var.project}-gpu-nodes-${var.environment}-sg"
  tooling_sg_name       = "${var.project}-tooling-${var.environment}-sg"
  bastion_host_sg_name  = "${var.project}-bastion-${var.environment}-sg"
  nats_sg_name          = "${var.project}-nats-${var.environment}-sg"
  vpc_endpoints_sg_name = "${var.project}-vpc-endpoints-${var.environment}-sg"

  # SSH CIDR handling with backward compatibility
  effective_ssh_cidrs = length(var.ssh_allowed_cidrs) > 0 ? var.ssh_allowed_cidrs : (
    var.bastion_allowed_ssh_cidrs != ["0.0.0.0/0"] ? var.bastion_allowed_ssh_cidrs : []
  )
  effective_bastion_cidrs = length(var.bastion_allowed_cidrs) > 0 ? var.bastion_allowed_cidrs : (
    var.bastion_allowed_ssh_cidrs != ["0.0.0.0/0"] ? var.bastion_allowed_ssh_cidrs : []
  )
}

# VPC Configuration
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.vpc_name
  cidr = local.vpc_cidr_block

  azs             = local.azs
  public_subnets  = slice(local.public_subnet_cidrs, 0, min(var.public_subnet_count, length(local.azs)))
  private_subnets = slice(local.private_subnet_cidrs, 0, min(var.private_subnet_count, length(local.azs)))

  enable_nat_gateway   = var.nat_type != "none"
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Kubernetes-specific tags
  public_subnet_tags = var.enable_kubernetes_tags ? {
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
  } : {}

  private_subnet_tags = var.enable_kubernetes_tags ? {
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
  } : {}

  tags = local.common_tags

  # Enable VPC Flow Logs for security monitoring
  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true
  flow_log_max_aggregation_interval    = 60
}

data "aws_ec2_managed_prefix_list" "s3" {
  name = "com.amazonaws.${var.region}.s3"
}

# Bastion Host (conditionally created)
resource "aws_instance" "bastion" {
  count = var.enable_bastion_host ? 1 : 0

  ami                         = var.base_aws_ami
  instance_type               = var.bastion_type
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.bastion_host.id]
  associate_public_ip_address = true
  key_name                    = var.ssh_key_name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = var.enable_volume_encryption
    kms_key_id            = var.kms_key_id
    delete_on_termination = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-bastion"
    Role = "bastion"
  })
}

###########################################
# Security Groups
###########################################

resource "aws_security_group" "control_plane" {
  name        = "${local.cluster_name}-control-plane"
  description = "Security group for Kubernetes control plane nodes"
  vpc_id      = module.vpc.vpc_id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = local.effective_ssh_cidrs
    description = "SSH access"
  }

  # Kubernetes API Server
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Kubernetes API Server"
  }

  # etcd
  ingress {
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    self        = true
    description = "etcd server client API"
  }

  # Kubelet API
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
    description = "Kubelet API"
  }

  # NATS messaging (if enabled)
  dynamic "ingress" {
    for_each = var.enable_nats_messaging ? [1] : []
    content {
      from_port   = var.nats_ports.client
      to_port     = var.nats_ports.client
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr]
      description = "NATS client port"
    }
  }

  dynamic "ingress" {
    for_each = var.enable_nats_messaging ? [1] : []
    content {
      from_port   = var.nats_ports.leafnode
      to_port     = var.nats_ports.leafnode
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr]
      description = "NATS leafnode port"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-control-plane"
  })
}

resource "aws_security_group" "worker_nodes" {
  name        = "${local.cluster_name}-worker-nodes"
  description = "Security group for Kubernetes worker nodes"
  vpc_id      = module.vpc.vpc_id

  # NATS messaging (if enabled)
  dynamic "ingress" {
    for_each = var.enable_nats_messaging ? [1] : []
    content {
      from_port   = var.nats_ports.client
      to_port     = var.nats_ports.client
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr]
      description = "NATS client port"
    }
  }

  dynamic "ingress" {
    for_each = var.enable_nats_messaging ? [1] : []
    content {
      from_port   = var.nats_ports.leafnode
      to_port     = var.nats_ports.leafnode
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr]
      description = "NATS leafnode port"
    }
  }

  # NodePort services
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "NodePort services"
  }

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "SSH access from VPC"
  }

  # Kubelet API
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Kubelet API"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name                                          = "${local.cluster_name}-worker-nodes"
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
  })
}

# GPU Nodes Security Group (if enabled)
resource "aws_security_group" "k8s_gpu_nodes" {
  count       = var.enable_gpu_nodes ? 1 : 0
  name        = local.gpu_nodes_sg_name
  description = "Security group for GPU worker nodes"
  vpc_id      = module.vpc.vpc_id

  # Inherit all rules from worker nodes
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.worker_nodes.id]
    description     = "All traffic from worker nodes"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = local.gpu_nodes_sg_name
    Role = "gpu-worker"
  })
}

# NATS Messaging Security Group (if enabled)
resource "aws_security_group" "nats_messaging" {
  count       = var.enable_nats_messaging ? 1 : 0
  name        = local.nats_sg_name
  description = "Security group for NATS messaging"
  vpc_id      = module.vpc.vpc_id

  tags = merge(local.common_tags, {
    Name = local.nats_sg_name
    Role = "messaging"
  })
}

resource "aws_security_group_rule" "nats_client" {
  count             = var.enable_nats_messaging ? 1 : 0
  security_group_id = aws_security_group.nats_messaging[0].id
  type              = "ingress"
  protocol          = "tcp"
  from_port         = var.nats_ports.client
  to_port           = var.nats_ports.client
  cidr_blocks       = [local.vpc_cidr_block]
  description       = "NATS client connections"
}

resource "aws_security_group_rule" "nats_cluster" {
  count             = var.enable_nats_messaging ? 1 : 0
  security_group_id = aws_security_group.nats_messaging[0].id
  type              = "ingress"
  protocol          = "tcp"
  from_port         = var.nats_ports.cluster
  to_port           = var.nats_ports.cluster
  self              = true
  description       = "NATS cluster routing"
}

resource "aws_security_group" "bastion_host" {
  name        = "${local.cluster_name}-bastion"
  description = "Security group for bastion host"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = local.effective_bastion_cidrs
    description = "SSH access to bastion"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name                                          = "${local.cluster_name}-bastion"
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
  })
}

# VPC Endpoints Security Group
resource "aws_security_group" "vpc_endpoints" {
  count       = var.enable_vpc_endpoints ? 1 : 0
  name        = local.vpc_endpoints_sg_name
  description = "Security group for VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  tags = merge(local.common_tags, {
    Name = local.vpc_endpoints_sg_name
    Role = "vpc-endpoints"
  })
}

resource "aws_security_group_rule" "vpc_endpoints_ingress" {
  count                    = var.enable_vpc_endpoints ? 1 : 0
  security_group_id        = aws_security_group.vpc_endpoints[0].id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 443
  to_port                  = 443
  source_security_group_id = aws_security_group.worker_nodes.id
  description              = "HTTPS from Kubernetes nodes"
}

# Tooling Security Group
resource "aws_security_group" "tooling" {
  name        = local.tooling_sg_name
  description = "Security group for tooling instances"
  vpc_id      = module.vpc.vpc_id

  tags = merge(local.common_tags, {
    Name = local.tooling_sg_name
    Role = "tooling"
  })
}

resource "aws_security_group_rule" "tooling_ssh" {
  security_group_id        = aws_security_group.tooling.id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 22
  to_port                  = 22
  source_security_group_id = aws_security_group.bastion_host.id
  description              = "SSH from bastion host"
}

resource "aws_security_group_rule" "tooling_api" {
  security_group_id        = aws_security_group.tooling.id
  type                     = "egress"
  protocol                 = "tcp"
  from_port                = var.k8s_api_server_port
  to_port                  = var.k8s_api_server_port
  source_security_group_id = aws_security_group.control_plane.id
  description              = "Kubernetes API access"
}

# Common egress rules for all security groups
locals {
  common_egress_rules = [
    {
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_blocks = ["0.0.0.0/0"]
      description = "HTTPS outbound"
    },
    {
      protocol    = "tcp"
      from_port   = 80
      to_port     = 80
      cidr_blocks = ["0.0.0.0/0"]
      description = "HTTP outbound"
    },
    {
      protocol    = "udp"
      from_port   = 53
      to_port     = 53
      cidr_blocks = ["169.254.169.253/32"]
      description = "DNS to VPC resolver"
    },
    {
      protocol    = "tcp"
      from_port   = 53
      to_port     = 53
      cidr_blocks = ["169.254.169.253/32"]
      description = "DNS TCP to VPC resolver"
    }
  ]
}

# Apply common egress rules to security groups
resource "aws_security_group_rule" "common_egress_control_plane" {
  for_each = { for idx, rule in local.common_egress_rules : idx => rule }

  security_group_id = aws_security_group.control_plane.id
  type              = "egress"
  protocol          = each.value.protocol
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  cidr_blocks       = each.value.cidr_blocks
  description       = each.value.description
}

resource "aws_security_group_rule" "common_egress_nodes" {
  for_each = { for idx, rule in local.common_egress_rules : idx => rule }

  security_group_id = aws_security_group.worker_nodes.id
  type              = "egress"
  protocol          = each.value.protocol
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  cidr_blocks       = each.value.cidr_blocks
  description       = each.value.description
}

# S3 Gateway VPC Endpoint (cost optimization)
resource "aws_vpc_endpoint" "s3_gateway" {
  count           = var.enable_vpc_endpoints ? 1 : 0
  vpc_id          = module.vpc.vpc_id
  service_name    = "com.amazonaws.${var.region}.s3"
  route_table_ids = module.vpc.private_route_table_ids

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-s3-gateway"
  })
}
