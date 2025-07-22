# modules/cpu-workers/outputs.tf

output "private_ips" {
  description = "Private IP addresses of the CPU worker instances."
  value       = module.cpu_worker_base.private_ips
}
