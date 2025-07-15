# modules/csi/switchboard/main.tf

locals {
  enabled_drivers = [
    var.enable_ebs ? "ebs" : null,
    var.enable_efs ? "efs" : null,
    var.enable_s3  ? "s3"  : null
  ]
}

module "ebs" {
  count  = var.enable_ebs ? 1 : 0
  source = "../ebs"

  storage_class_name   = var.ebs_storage_class_name
  service_account_name = var.ebs_service_account_name
}

module "efs" {
  count  = var.enable_efs ? 1 : 0
  source = "../efs"

  aws_region         = var.aws_region
  cluster_name       = var.cluster_name
  subnet_ids         = var.subnet_ids
  security_group_id  = var.security_group_id
  storage_class_name = var.efs_storage_class_name
}

module "s3" {
  count  = var.enable_s3 ? 1 : 0
  source = "../s3-mountpoint"

  aws_region         = var.aws_region
  bucket_name        = var.s3_bucket_name
  storage_class_name = var.s3_storage_class_name
}

output "enabled_storage_classes" {
  value = {
    ebs = var.enable_ebs ? module.ebs[0].storage_class_name : null
    efs = var.enable_efs ? module.efs[0].storage_class_name : null
    s3  = var.enable_s3  ? module.s3[0].storage_class_name  : null
  }
}
