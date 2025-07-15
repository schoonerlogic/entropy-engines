# Outputs
output "instance_id" {
  value       = aws_instance.model_downloader.id
  description = "ID of the model downloader instance"
}

output "public_ip" {
  value       = aws_instance.model_downloader.public_ip
  description = "Public IP of the model downloader instance"
}


