# modules/vpc-endpoints/variables.tf
# VPC Endpoints module variables

#===============================================================================
# Core Configuration Variables
#===============================================================================

variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for VPC endpoints"
  type        = list(string)
}

variable "route_table_ids" {
  description = "List of route table IDs for gateway endpoints"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for VPC endpoints"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

#===============================================================================
# Cost Optimization Variables (individual instead of config object)
#===============================================================================

variable "enable_spot_instances" {
  description = "Enable spot instances for cost optimization"
  type        = bool
  default     = true
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for cost optimization"
  type        = bool
  default     = false
}

#===============================================================================
# Optional Configuration Variables
#===============================================================================

variable "tags" {
  description = "Tags to apply to VPC endpoint resources"
  type        = map(string)
  default     = {}
}
