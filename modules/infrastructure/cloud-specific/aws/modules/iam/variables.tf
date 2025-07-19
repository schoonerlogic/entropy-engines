
# modules/iam/variables.tf
variable "aws_region" {
  description = "AWS region used for building KMS and SSM ARNs"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "project" {
  type    = string
  default = "Astral-Maris"
}

variable "environment" {
  type    = string
  default = "dev"
}


