variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for interface endpoints"
  type        = list(string)
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for interface endpoints"
  type        = string
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

variable "route_table_ids" {
  description = "List of route table IDs for gateway endpoints"
  type        = list(string)
}

variable "enable_vpc_endpoints" {
  description = "Toggle for VPC endpoint creation"
  type        = bool
  default     = true
}

variable "cost_optimization" {
  description = "Cost optimization settings"
  type = object({
    enable_spot_instances = optional(bool, true)
    enable_vpc_endpoints  = optional(bool, true)
  })
  default = {}
}
