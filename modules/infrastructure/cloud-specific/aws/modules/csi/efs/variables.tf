
# modules/csi/efs/variables.tf

variable "aws_region" {
  description = "AWS region for EFS"
  type        = string
}

variable "cluster_name" {
  description = "Name of the cluster for naming EFS"
  type        = string
}

variable "subnet_ids" {
  description = "List of private subnet IDs for mounting EFS"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group to attach to mount targets"
  type        = string
}

variable "namespace" {
  description = "Namespace to deploy EFS CSI driver"
  type        = string
  default     = "kube-system"
}

variable "storage_class_name" {
  description = "StorageClass name for EFS"
  type        = string
  default     = "efs-sc"
}

variable "helm_chart_version" {
  description = "Helm chart version for AWS EFS CSI Driver"
  type        = string
  default     = "2.4.5"
}

# modules/csi/efs/outputs.tf

output "storage_class_name" {
  description = "Name of the EFS CSI StorageClass"
  value       = kubernetes_storage_class.efs_sc.metadata[0].name
}

output "file_system_id" {
  description = "ID of the created EFS file system"
  value       = aws_efs_file_system.graphscope_efs.id
}
