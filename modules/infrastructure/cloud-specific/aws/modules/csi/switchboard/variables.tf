# modules/csi/switchboard/variables.tf

variable "enable_ebs" {
  type    = bool
  default = true
}

variable "enable_efs" {
  type    = bool
  default = true
}

variable "enable_s3" {
  type    = bool
  default = true
}

variable "aws_region" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "s3_bucket_name" {
  type = string
}

variable "ebs_storage_class_name" {
  type    = string
  default = "gp3-ebs"
}

variable "ebs_service_account_name" {
  type    = string
  default = "ebs-csi-controller-sa"
}

variable "efs_storage_class_name" {
  type    = string
  default = "efs-sc"
}

variable "s3_storage_class_name" {
  type    = string
  default = "s3-mountpoint"
}
