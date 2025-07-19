
# modules/csi/ebs/variables.tf

variable "helm_chart_version" {
  description = "Helm chart version for AWS EBS CSI Driver"
  type        = string
  default     = "2.30.0"
}

variable "storage_class_name" {
  description = "Name of the StorageClass to create"
  type        = string
  default     = "ebs-sc"
}

variable "service_account_name" {
  description = "Service account name for the CSI driver"
  type        = string
  default     = "ebs-csi-controller-sa"
}

# modules/csi/ebs/outputs.tf

output "storage_class_name" {
  description = "EBS StorageClass name"
  value       = kubernetes_storage_class.ebs_sc.metadata[0].name
}
