# modules/iam/variables.tf
# IAM module variables updated to use individual variables

#===============================================================================
# Core Configuration Variables
#===============================================================================

variable "project" {
  description = "Project name used for resource naming"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

#===============================================================================
# IAM Role Configuration Variables
#===============================================================================

variable "control_plane_role_name" {
  description = "Name of the control plane IAM role"
  type        = string
  default     = null
}

variable "worker_role_name" {
  description = "Name of the worker IAM role"
  type        = string
  default     = null
}

variable "gpu_worker_role_name" {
  description = "Name of the GPU worker IAM role"
  type        = string
  default     = null
}

variable "cluster_name" {
  description = "Kubernetes cluster name for IAM policies"
  type        = string
  default     = null
}

#===============================================================================
# Optional Configuration Variables
#===============================================================================

variable "tags" {
  description = "Tags to apply to IAM resources"
  type        = map(string)
  default     = {}
}
