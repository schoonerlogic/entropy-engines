# modules/vpc-endpoints/main.tf
locals {
  # Extract the enable flag
  create_vpc_endpoints = var.cost_optimization.enable_vpc_endpoints
}

# S3 Gateway endpoint (free)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids

  tags = merge(
    {
      Name       = "s3-gateway-endpoint"
      Tier       = "internal"
      Network    = "private"
      Compliance = "pci"
    },
    var.tags
  )
}

# SSM endpoint for k8s join command
resource "aws_vpc_endpoint" "ssm" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [var.security_group_id]
  private_dns_enabled = true

  tags = merge(
    {
      Name = "ssm-endpoint"
    },
    var.tags
  )
}



# ECR API endpoint
resource "aws_vpc_endpoint" "ecr_api" {
  count = var.enable_vpc_endpoints ? 0 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [var.security_group_id]
  private_dns_enabled = true

  tags = merge(
    {
      Name = "ecr-api-endpoint"
    },
    var.tags
  )
}

# ECR DKR endpoint
resource "aws_vpc_endpoint" "ecr_dkr" {
  count = var.enable_vpc_endpoints ? 0 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [var.security_group_id]
  private_dns_enabled = true

  tags = merge(
    {
      Name = "ecr-dkr-endpoint"
    },
    var.tags
  )
}

# STS endpoint for authentication
resource "aws_vpc_endpoint" "sts" {
  count = var.enable_vpc_endpoints ? 0 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [var.security_group_id]
  private_dns_enabled = true

  tags = merge(
    {
      Name = "sts-endpoint"
    },
    var.tags
  )
}

# EC2 endpoint for cluster operations
resource "aws_vpc_endpoint" "ec2" {
  count = var.enable_vpc_endpoints ? 0 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [var.security_group_id]
  private_dns_enabled = true

  tags = merge(
    {
      Name = "ec2-endpoint"
    },
    var.tags
  )
}

# CloudWatch logs endpoint
resource "aws_vpc_endpoint" "logs" {
  count = var.enable_vpc_endpoints ? 0 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [var.security_group_id]
  private_dns_enabled = true

  tags = merge(
    {
      Name = "logs-endpoint"
    },
    var.tags
  )
}

# Optional: ELB endpoint if using AWS load balancers
resource "aws_vpc_endpoint" "elasticloadbalancing" {
  count = var.enable_vpc_endpoints ? 0 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.elasticloadbalancing"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [var.security_group_id]
  private_dns_enabled = true

  tags = merge(
    {
      Name = "elb-endpoint"
    },
    var.tags
  )
}

