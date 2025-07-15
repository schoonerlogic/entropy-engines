# modules/ml-infrastructure/main.tf


# Create VPC endpoints
module "vpc_endpoints" {
  source = "../vpc-endpoints"
  
  vpc_id           = var.vpc_id
  subnet_ids       = var.subnet_ids
  route_table_ids  = var.route_table_ids
  region           = var.region
  security_group_id = var.security_group_id
}

# Create S3 bucket for model storage
module "model_storage" {
  source = "../model-storage"
  
  bucket_name = "${var.cluster_name}-model-storage"
  tags = {
    Cluster = var.cluster_name
    Purpose = "ML Model Storage"
  }
}

# Create model downloader instance
module "model_downloader" {
  source = "../model-downloader"
  
  cluster_name    = var.cluster_name
  models          = var.models
  s3_bucket_name  = module.model_storage.bucket_name
}
