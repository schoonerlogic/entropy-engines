# Kubernetes Cluster Module Outputs

output "kubeadm_token" {
  description = "Kubeadm token for joining nodes"
  value       = local.kubeadm_token
  sensitive   = true
}

output "certificate_key" {
  description = "Certificate key for joining control plane nodes"
  value       = local.certificate_key
  sensitive   = true
}

output "control_plane_user_data" {
  description = "User data for control plane initialization"
  value       = local.control_plane_user_data
}

output "worker_user_data" {
  description = "User data for worker node joining"
  value       = local.worker_user_data
}

output "kubernetes_version" {
  description = "Kubernetes version"
  value       = var.kubernetes_version
}

output "pod_cidr" {
  description = "Pod CIDR range"
  value       = var.pod_cidr
}

output "service_cidr" {
  description = "Service CIDR range"
  value       = var.service_cidr
}