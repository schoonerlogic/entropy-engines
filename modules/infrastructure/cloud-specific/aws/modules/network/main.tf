# Enhanced AWS VPC Module for Cloud-Agnostic Kubernetes
# Security-hardened with cloud-agnostic variables

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Use provided availability zones or discover available ones
  azs = var.availability_zones != null ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, max(var.public_subnet_count, var.private_subnet_count))

  # Use provided CIDRs or defaults
  vpc_cidr_block     = local.vpc_cidr
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
    Architecture                                  = var.instance_ami_architecture
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

# modules/network/main.tf - Use organized configs with fallbacks
locals {
  # Use organized config values with fallbacks to individual variables
  vpc_cidr = var.network_config.vpc_cidr

  # For SSH key, prefer organized config but fall back to individual variable
  ssh_key_name = var.security_config.ssh_key_name != "" ? var.security_config.ssh_key_name : var.ssh_key_name

  # For NAT type, prefer organized config but fall back to individual variable
  nat_type = var.nat_config.nat_type

  # For bastion, use organized config
  enable_bastion        = var.security_config.enable_bastion_host
  bastion_instance_type = var.security_config.bastion_instance_type

  # Availability zones - use from config or data source
  availability_zones = var.network_config.availability_zones != null ? var.network_config.availability_zones : data.aws_availability_zones.available.names
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


  # enable vpc FLOW LOGS FOR SECURITY MONITORING
  # ENABLE_FLOW_LOG                      = TRUE
  # CREATE_FLOW_LOG_CLOUDWATCH_IAM_ROLE  = TRUE
  # CREATE_FLOW_LOG_CLOUDWATCH_LOG_GROUP = TRUE
  # flow_log_max_aggregation_interval    = 60
}

# Data sources for AMI and AWS services
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-${var.ubuntu_codename}-${var.ubuntu_version}-${var.instance_ami_architecture}-server-*"]
  }

  filter {
    name   = "architecture"
    values = [var.instance_ami_architecture]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ec2_managed_prefix_list" "s3" {
  name = "com.amazonaws.${var.region}.s3"
}

# EIP for NAT Gateway (only if using gateway)
resource "aws_eip" "nat_eip" {
  count  = var.nat_type == "gateway" ? 1 : 0
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-nat-eip"
  })
}

# NAT Gateway
resource "aws_nat_gateway" "nat_gateway" {
  count         = var.nat_type == "gateway" ? 1 : 0
  allocation_id = aws_eip.nat_eip[0].id
  subnet_id     = module.vpc.public_subnets[0]

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-nat-gateway"
  })
}

# Route for private subnets
# resource "aws_route" "private_nat" {
#   count                  = var.nat_type == "gateway" ? length(module.vpc.private_route_table_ids) : 0
#   route_table_id         = module.vpc.private_route_table_ids[count.index]
#   destination_cidr_block = "0.0.0.0/0"
#   nat_gateway_id         = aws_nat_gateway.nat_gateway[0].id
# }

# Bastion Host (conditionally created)
resource "aws_instance" "bastion" {
  count = var.enable_bastion_host ? 1 : 0

  ami                         = data.aws_ami.ubuntu.id
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
# Your existing resources, but using the new locals
resource "aws_vpc" "main" {
  cidr_block           = local.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.vpc_name}"
  })
}


###########################################
# Security Groups
###########################################


resource "aws_security_group" "control_plane" {
  name        = "${local.cluster_name}-control-plane"
  description = "Security group for Kubernetes control plane nodes"
  vpc_id      = module.vpc.vpc_id

  # Kubernetes API
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  # Kubernetes API Server
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # etcd
  ingress {
    from_port = 2379
    to_port   = 2380
    protocol  = "tcp"
    self      = true
  }

  # Kubelet API
  ingress {
    from_port = 10250
    to_port   = 10250
    protocol  = "tcp"
    self      = true
  }

  # NATS messaging
  ingress {
    from_port   = 4222
    to_port     = 4222
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = 7422
    to_port     = 7422
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
}


resource "aws_security_group" "worker_nodes" {
  name        = "${local.cluster_name}-worker-nodes"
  description = "Security group for Kubernetes worker nodes"
  vpc_id      = module.vpc.vpc_id

  # NATS messaging
  ingress {
    from_port   = 4222
    to_port     = 4222
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = 7422
    to_port     = 7422
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # NodePort services
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name                                        = "${local.cluster_name}-worker-nodes"
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
  })
}


# GPU Nodes Security Group (if enabled)
resource "aws_security_group" "k8s_gpu_nodes" {
  count       = var.enable_gpu_nodes ? 1 : 0
  name        = local.gpu_nodes_sg_name
  description = "Security group for GPU worker nodes"
  vpc_id      = module.vpc.vpc_id

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
    cidr_blocks = var.bastion_allowed_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name                                        = "${local.cluster_name}-bastion"
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

