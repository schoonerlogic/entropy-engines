# Outputs
output "bucket_name" {
  value       = aws_s3_bucket.model_storage.bucket
  description = "Name of the S3 bucket for model storage"
}

output "bucket_arn" {
  value       = aws_s3_bucket.model_storage.arn
  description = "ARN of the S3 bucket for model storage"
}

output "reader_policy_arn" {
  value       = aws_iam_policy.model_bucket_access.arn
  description = "ARN of the IAM policy for reading from the model bucket"
}

output "uploader_policy_arn" {
  value       = aws_iam_policy.model_uploader_access.arn
  description = "ARN of the IAM policy for uploading to the model bucket"
}
