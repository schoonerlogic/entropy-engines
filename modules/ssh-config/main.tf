# modules/ssh-config/main.tf
# resource "local_file" "ssh_config" {
#   filename = "${path.root}/ssh_config"
#   content = templatefile("${path.module}/templates/ssh_config.tpl", {
#     cluster_name         = var.cluster_name,
#     bastion_host         = var.bastion_host,
#     bastion_user         = var.bastion_user,
#     k8s_user             = var.k8s_user,
#     ssh_private_key_path = var.ssh_private_key_path,
#     ssh_key_name         = var.ssh_private_key_path,
#
#     controller_private_ips = var.controller_private_ips,
#     worker_gpu_private_ips = var.worker_gpu_private_ips,
#     worker_cpu_private_ips = var.worker_cpu_private_ips,
#     nats_private_ips       = var.nats_private_ips,
#
#     controllers = length(var.controller_private_ips) > 0 ? [
#       for i, ip in var.controller_private_ips : {
#         index      = i,
#         private_ip = ip
#       }
#     ] : [],
#     has_controllers = length(var.controller_private_ips) > 0,
#
#     worker_gpus = length(var.worker_gpu_private_ips) > 0 ? [
#       for i, ip in var.worker_gpu_private_ips : {
#         index      = i,
#         private_ip = ip
#       }
#     ] : [],
#     has_worker_gpus = length(var.worker_gpu_private_ips) > 0,
#
#     worker_cpus = length(var.worker_cpu_private_ips) > 0 ? [
#       for i, ip in var.worker_cpu_private_ips : {
#         index      = i,
#         private_ip = ip
#       }
#     ] : [],
#     has_worker_cpus = length(var.worker_cpu_private_ips) > 0,
#
#     nats_servers = length(var.nats_private_ips) > 0 ? [
#       for i, ip in var.nats_private_ips : {
#         index      = i,
#         private_ip = ip
#       }
#     ] : [],
#     has_nats_servers = length(var.nats_private_ips) > 0,
#   })
# }
#
# output "ssh_instructions" {
#   value = <<-EOT
#     # SSH config file created at: ${path.module}/k8s_ssh_config
#
#     # Use it directly:
#     ssh -F ${path.module}/k8s_ssh_config controller-0
#     ssh -F ${path.module}/k8s_ssh_config gpu-worker-0
#     ssh -F ${path.module}/k8s_ssh_config cpu-worker-0
#    EOT
# }
#
# output "ssh_config_file" {
#   value     = local_file.ssh_config.content
#   sensitive = false # Set to true if the content contains sensitive information
# }
