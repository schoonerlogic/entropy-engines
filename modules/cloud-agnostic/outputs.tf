# Kubernetes Cluster Module Outputs

output "kubeadm_token" {
  description = "Kubeadm token for joining nodes"
  value       = module.kubernetes-cluster.kubeadm_token
  sensitive   = true
}

output "certificate_key" {
  description = "Certificate key for joining control plane nodes"
  value       = module.kubernetes-cluster.certificate_key
  sensitive   = true
}

output "control_plane_user_data" {
  description = "User data for control plane initialization"
  value       = module.kubernetes-cluster.control_plane_user_data
}

output "worker_user_data" {
  description = "User data for worker node joining"
  value       = module.kubernetes-cluster.worker_user_data
}

output "kubernetes_version" {
  description = "Kubernetes version"
  value       = module.kubernetes-cluster.kubernetes_version
}

output "pod_cidr" {
  description = "Pod CIDR range"
  value       = module.kubernetes-cluster.pod_cidr
}

output "service_cidr" {
  description = "Service CIDR range"
  value       = module.kubernetes-clusterr.service_cidr
}
