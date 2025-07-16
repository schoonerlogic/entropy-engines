# Cloud-Agnostic Kubernetes Cluster Module
# This module creates a self-managed Kubernetes cluster using kubeadm

# Generate a random token for kubeadm
resource "random_string" "kubeadm_token" {
  length  = 6
  special = false
  upper   = false
}

resource "random_string" "kubeadm_token_id" {
  length  = 16
  special = false
  upper   = false
}

# Generate a random certificate key (32 bytes hex encoded)
resource "random_string" "certificate_key" {
  length  = 64
  special = false
  upper   = false
  lower   = true
  number  = true
}

# Template for control plane initialization
locals {
  kubeadm_token   = "${random_string.kubeadm_token.result}.${random_string.kubeadm_token_id.result}"
  certificate_key = random_string.certificate_key.result

  # Cloud-specific configurations
  cloud_configs = {
    aws = {
      cloud_provider    = "aws"
      cloud_config_path = "/etc/kubernetes/aws.conf"
    }
    gcp = {
      cloud_provider    = "gce"
      cloud_config_path = "/etc/kubernetes/gce.conf"
    }
    azure = {
      cloud_provider    = "azure"
      cloud_config_path = "/etc/kubernetes/azure.conf"
    }
  }

  cloud_config = local.cloud_configs[var.cloud_provider]

  control_plane_endpoint = var.control_plane_private_ip

  control_plane_user_data = base64encode(templatefile("${path.module}/templates/control-plane-init.sh.tftpl", {
    cluster_name       = var.cluster_name
    kubernetes_version = var.kubernetes_version
    pod_cidr           = var.pod_cidr
    service_cidr       = var.service_cidr
    kubeadm_token      = local.kubeadm_token
    certificate_key    = "" # Let kubeadm generate it
    cloud_provider     = "aws"
    cloud_config_path  = "/etc/kubernetes/aws.conf"
  }))

  worker_user_data = base64encode(templatefile("${path.module}/templates/worker-join.sh.tftpl", {
    cluster_name                 = var.cluster_name
    kubernetes_version           = var.kubernetes_version
    kubeadm_token                = local.kubeadm_token
    certificate_key              = local.certificate_key
    cloud_provider               = "aws"
    cloud_config_path            = "/etc/kubernetes/aws.conf"
    control_plane_endpoint       = var.control_plane_private_ip
    discovery_token_ca_cert_hash = var.discovery_token_ca_cert_hash
  }))
}