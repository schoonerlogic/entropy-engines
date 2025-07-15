variable "instance_name" {
  description = "Name of the model downloader instance"
  type        = string
  default     = "model-downloader"
}

variable "vpc_id" {
  description = "VPC ID where the downloader instance will be deployed"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the downloader instance"
  type        = string
}

variable "models" {
  description = "List of Hugging Face models to download"
  type        = list(object({
    model_id    = string
    destination = string
  }))
  default = []
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket where models will be stored"
  type        = string
}

variable "iam_policy_arn" {
  description = "ARN of the IAM policy for uploading to the model bucket"
  type        = string
}

variable "instance_type" {
  description = "Instance type for the model downloader"
  type        = string
  default     = "c7g.large"  # ARM-based Graviton instance
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}


