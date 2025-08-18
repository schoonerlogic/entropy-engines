output "controller_instance_private_ips" {
  description = "List of controller private IP addresses"
  value       = module.controllers.private_ips
}

output "cpu_instance_private_ips" {
  description = "List of CPU worker private IP addresses"
  value       = flatten([for m in module.cpu_workers : m.instance_private_ips])
}

output "gpu_instance_private_ips" {
  description = "List of GPU worker private IP addresses"
  value       = flatten([for m in module.gpu_workers : m.instance_private_ips])
}
