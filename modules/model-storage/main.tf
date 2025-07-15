# modules/model-storage/main.tf
# S3 bucket and IAM policy for storing Hugging Face models

# Create S3 bucket for model storage
resource "aws_s3_bucket" "model_storage" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  tags = var.tags
}

# Enable versioning to maintain model history
resource "aws_s3_bucket_versioning" "model_versioning" {
  bucket = aws_s3_bucket.model_storage.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "model_encryption" {
  bucket = aws_s3_bucket.model_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access to the bucket
resource "aws_s3_bucket_public_access_block" "model_storage" {
  bucket = aws_s3_bucket.model_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM policy for K8s nodes to access models
resource "aws_iam_policy" "model_bucket_access" {
  name        = "${var.bucket_name}-access"
  description = "Allow K8s nodes to access the model bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetObjectVersion"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.model_storage.arn,
          "${aws_s3_bucket.model_storage.arn}/*"
        ]
      }
    ]
  })
}

# IAM policy for model uploader to add models to bucket
resource "aws_iam_policy" "model_uploader_access" {
  name        = "${var.bucket_name}-uploader-access"
  description = "Allow model uploader to put objects in the model bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:ListBucket",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.model_storage.arn,
          "${aws_s3_bucket.model_storage.arn}/*"
        ]
      }
    ]
  })
}
