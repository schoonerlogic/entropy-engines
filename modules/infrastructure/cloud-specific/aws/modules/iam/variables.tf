# modules/iam/variables.tf

# Core configuration
variable "project" {
  description = "Name of the project"
  type        = string
}

variable "aws_region" {
  description = "AWS region for the deployment"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "tags" {
  description = "A map of tags to assign to the resources"
  type        = map(string)
  default     = {}
}

# Role names
variable "control_plane_role_name" {
  description = "Name of the IAM role for the control plane"
  type        = string
  default     = null
}

variable "worker_role_name" {
  description = "Name of the IAM role for worker nodes"
  type        = string
  default     = null
}

variable "gpu_worker_role_name" {
  description = "Name of the IAM role for GPU worker nodes"
  type        = string
  default     = null
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = null
}

variable "bootstrap_bucket_name" {
  description = "Name of the S3 bucket for bootstrap"
  type        = string
}