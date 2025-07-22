# modules/vpc-endpoints/main.tf
# VPC Endpoints for cost optimization

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}



locals {
  enable_vpc_endpoints = false
  # Common tags
  common_tags = merge({
    ManagedBy = "terraform"
    Module    = "vpc-endpoints"
  }, var.tags)
}

# S3 Gateway VPC Endpoint (free and reduces NAT gateway costs)
resource "aws_vpc_endpoint" "s3" {
  count = local.enable_vpc_endpoints ? 1 : 0

  vpc_id          = var.vpc_id
  service_name    = "com.amazonaws.${var.region}.s3"
  route_table_ids = var.route_table_ids

  tags = merge(local.common_tags, {
    Name = "s3-gateway-endpoint"
    Type = "Gateway"
  })
}

# DynamoDB Gateway VPC Endpoint (free and reduces NAT gateway costs)
resource "aws_vpc_endpoint" "dynamodb" {
  count = local.enable_vpc_endpoints ? 1 : 0

  vpc_id          = var.vpc_id
  service_name    = "com.amazonaws.${var.region}.dynamodb"
  route_table_ids = var.route_table_ids

  tags = merge(local.common_tags, {
    Name = "dynamodb-gateway-endpoint"
    Type = "Gateway"
  })
}

# EC2 Interface VPC Endpoint (reduces NAT gateway costs for EC2 API calls)
resource "aws_vpc_endpoint" "ec2" {
  count = local.enable_vpc_endpoints ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [var.security_group_id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "ec2-interface-endpoint"
    Type = "Interface"
  })
}

# ECR API Interface VPC Endpoint (for container image management)
resource "aws_vpc_endpoint" "ecr_api" {
  count = local.enable_vpc_endpoints ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [var.security_group_id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "ecr-api-interface-endpoint"
    Type = "Interface"
  })
}

# ECR DKR Interface VPC Endpoint (for Docker registry)
resource "aws_vpc_endpoint" "ecr_dkr" {
  count = local.enable_vpc_endpoints ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [var.security_group_id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "ecr-dkr-interface-endpoint"
    Type = "Interface"
  })
}

# SSM Interface VPC Endpoint (for Systems Manager)
resource "aws_vpc_endpoint" "ssm" {
  count = local.enable_vpc_endpoints ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [var.security_group_id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "ssm-interface-endpoint"
    Type = "Interface"
  })
}

# SSM Messages Interface VPC Endpoint
resource "aws_vpc_endpoint" "ssm_messages" {
  count = local.enable_vpc_endpoints ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [var.security_group_id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "ssm-messages-interface-endpoint"
    Type = "Interface"
  })
}

# EC2 Messages Interface VPC Endpoint
resource "aws_vpc_endpoint" "ec2_messages" {
  count = local.enable_vpc_endpoints ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [var.security_group_id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "ec2-messages-interface-endpoint"
    Type = "Interface"
  })
}

# CloudWatch Logs Interface VPC Endpoint
resource "aws_vpc_endpoint" "logs" {
  count = local.enable_vpc_endpoints ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [var.security_group_id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "logs-interface-endpoint"
    Type = "Interface"
  })
}

# CloudWatch Monitoring Interface VPC Endpoint
resource "aws_vpc_endpoint" "monitoring" {
  count = local.enable_vpc_endpoints ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.monitoring"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [var.security_group_id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "monitoring-interface-endpoint"
    Type = "Interface"
  })
}
