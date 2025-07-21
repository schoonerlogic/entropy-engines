# modules/vpc-endpoints/outputs.tf
# VPC Endpoints module outputs

#===============================================================================
# Gateway Endpoints
#===============================================================================

output "s3_vpc_endpoint_id" {
  description = "The ID of the S3 VPC endpoint"
  value       = var.enable_vpc_endpoints ? aws_vpc_endpoint.s3[0].id : null
}

output "dynamodb_vpc_endpoint_id" {
  description = "The ID of the DynamoDB VPC endpoint"
  value       = var.enable_vpc_endpoints ? aws_vpc_endpoint.dynamodb[0].id : null
}

#===============================================================================
# Interface Endpoints
#===============================================================================

output "ec2_vpc_endpoint_id" {
  description = "The ID of the EC2 VPC endpoint"
  value       = var.enable_vpc_endpoints ? aws_vpc_endpoint.ec2[0].id : null
}

output "ecr_api_vpc_endpoint_id" {
  description = "The ID of the ECR API VPC endpoint"
  value       = var.enable_vpc_endpoints ? aws_vpc_endpoint.ecr_api[0].id : null
}

output "ecr_dkr_vpc_endpoint_id" {
  description = "The ID of the ECR DKR VPC endpoint"
  value       = var.enable_vpc_endpoints ? aws_vpc_endpoint.ecr_dkr[0].id : null
}

output "ssm_vpc_endpoint_id" {
  description = "The ID of the SSM VPC endpoint"
  value       = var.enable_vpc_endpoints ? aws_vpc_endpoint.ssm[0].id : null
}

output "ssm_messages_vpc_endpoint_id" {
  description = "The ID of the SSM Messages VPC endpoint"
  value       = var.enable_vpc_endpoints ? aws_vpc_endpoint.ssm_messages[0].id : null
}

output "ec2_messages_vpc_endpoint_id" {
  description = "The ID of the EC2 Messages VPC endpoint"
  value       = var.enable_vpc_endpoints ? aws_vpc_endpoint.ec2_messages[0].id : null
}

output "logs_vpc_endpoint_id" {
  description = "The ID of the CloudWatch Logs VPC endpoint"
  value       = var.enable_vpc_endpoints ? aws_vpc_endpoint.logs[0].id : null
}

output "monitoring_vpc_endpoint_id" {
  description = "The ID of the CloudWatch Monitoring VPC endpoint"
  value       = var.enable_vpc_endpoints ? aws_vpc_endpoint.monitoring[0].id : null
}

#===============================================================================
# Summary Outputs
#===============================================================================

output "gateway_endpoints" {
  description = "List of gateway VPC endpoint IDs"
  value = var.enable_vpc_endpoints ? [
    aws_vpc_endpoint.s3[0].id,
    aws_vpc_endpoint.dynamodb[0].id
  ] : []
}

output "interface_endpoints" {
  description = "List of interface VPC endpoint IDs"
  value = var.enable_vpc_endpoints ? [
    aws_vpc_endpoint.ec2[0].id,
    aws_vpc_endpoint.ecr_api[0].id,
    aws_vpc_endpoint.ecr_dkr[0].id,
    aws_vpc_endpoint.ssm[0].id,
    aws_vpc_endpoint.ssm_messages[0].id,
    aws_vpc_endpoint.ec2_messages[0].id,
    aws_vpc_endpoint.logs[0].id,
    aws_vpc_endpoint.monitoring[0].id
  ] : []
}

output "total_endpoints_created" {
  description = "Total number of VPC endpoints created"
  value       = var.enable_vpc_endpoints ? 10 : 0
}
