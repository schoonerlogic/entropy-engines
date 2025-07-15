# Output the model bucket name for use in K8s
output "model_bucket_name" {
  value = module.model_storage.bucket_name
}

output "model_access_policy_arn" {
  value = module.model_storage.access_policy_arn
}
