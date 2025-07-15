output "private_ips" {
  description = "Private IP addresses of the worker GPU instances in the spot fleet"
  value       = data.aws_instances.workers.private_ips
}

output "public_ips" {
  description = "Public IP addresses of the worker GPU instances in the spot fleet"
  value       = data.aws_instances.worker_gpu_fleet_instances.public_ips[*]
}

output "instance_ids" {
  description = "Instance IDs of the worker GPU instances in the spot fleet"
  value       = data.aws_instances.worker_gpu_fleet_instances.ids[*]
}

