# NATS Messaging Module Outputs

output "nats_private_ips" {
  description = "Private IP addresses of NATS servers"
  value       = var.cloud_provider == "aws" ? aws_instance.nats[*].private_ip : []
}

output "nats_public_ips" {
  description = "Public IP addresses of NATS servers"
  value       = var.cloud_provider == "aws" ? aws_instance.nats[*].public_ip : []
}

output "nats_endpoint" {
  description = "NATS cluster endpoint"
  value       = var.cloud_provider == "aws" ? join(",", aws_instance.nats[*].private_ip) : ""
}

output "nats_client_url" {
  description = "NATS client connection URL"
  value       = var.cloud_provider == "aws" ? "nats://${join(",", aws_instance.nats[*].private_ip)}:4222" : ""
}