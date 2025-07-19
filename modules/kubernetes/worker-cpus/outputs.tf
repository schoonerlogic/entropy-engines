output "worker_details" {
  description = "Map of worker instances with their IDs and private IPs, keyed by index."
  value       = local.worker_details_map
}

output "worker_cpu_spot_details" {
  value = local.worker_details_map
}

output "private_ips" {
  description = "Private IP addresses of the worker CPU instances in the spot fleet"
  value       = data.aws_instances.workers.private_ips
}

output "public_ips" {
  description = "Public IP addresses of the worker CPU instances in the spot fleet"
  value       = data.aws_instances.worker_cpu_fleet_instances.public_ips[*]
}

output "instance_ids" {
  description = "Instance IDs of the worker CPU instances in the spot fleet"
  value       = data.aws_instances.worker_cpu_fleet_instances.ids[*]
}

