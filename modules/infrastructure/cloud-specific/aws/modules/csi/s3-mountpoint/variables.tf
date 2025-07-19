# modules/csi/s3-mountpoint/variables.tf

variable "namespace" {
  description = "Namespace to install the driver"
  type        = string
  default     = "kube-system"
}

variable "helm_chart_version" {
  description = "Version of the mountpoint-s3-csi-driver chart"
  type        = string
  default     = "0.1.0"
}

variable "aws_region" {
  description = "AWS region to configure driver"
  type        = string
}

variable "bucket_name" {
  description = "S3 bucket name to mount"
  type        = string
}

variable "storage_class_name" {
  description = "Name of the S3 storage class"
  type        = string
  default     = "s3-mountpoint"
}

# modules/csi/s3-mountpoint/outputs.tf

output "storage_class_name" {
  description = "Name of the S3 CSI StorageClass"
  value       = kubernetes_storage_class.s3_sc.metadata[0].name
}

