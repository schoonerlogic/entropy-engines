# Cloud-Agnostic Kubernetes Cluster Module
# This module creates a self-managed Kubernetes cluster using kubeadm

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version to install"
  type        = string
  default     = "1.29.0"
}

variable "control_plane_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 3
}

variable "control_plane_instance_type" {
  description = "Instance type for control plane nodes"
  type        = string
  default     = "t3.medium"
}

variable "pod_cidr" {
  description = "CIDR range for pods"
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "CIDR range for services"
  type        = string
  default     = "10.96.0.0/12"
}

variable "ssh_key_name" {
  description = "Name of the SSH key pair"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the cluster"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs"
  type        = list(string)
}

variable "iam_instance_profile" {
  description = "IAM instance profile name"
  type        = string
}

variable "cloud_provider" {
  description = "Cloud provider (aws, gcp, azure)"
  type        = string
}

variable "cloud_config" {
  description = "Cloud-specific configuration"
  type = object({
    region              = string
    availability_zones  = list(string)
    instance_profile    = string
    security_group_ids  = list(string)
    subnet_ids          = list(string)
    vpc_id              = string
  })
}

# Generate a random token for kubeadm
resource "random_string" "kubeadm_token" {
  length  = 6
  special = false
  upper   = false
}

# Generate a random certificate key
resource "random_string" "certificate_key" {
  length  = 64
  special = false
  upper   = false
}

# Template for control plane initialization
locals {
  kubeadm_token      = random_string.kubeadm_token.result
  certificate_key    = random_string.certificate_key.result
  
  # Cloud-specific configurations
  cloud_configs = {
    aws = {
      cloud_provider = "aws"
      cloud_config_path = "/etc/kubernetes/aws.conf"
    }
    gcp = {
      cloud_provider = "gce"
      cloud_config_path = "/etc/kubernetes/gce.conf"
    }
    azure = {
      cloud_provider = "azure"
      cloud_config_path = "/etc/kubernetes/azure.conf"
    }
  }
  
  cloud_config = local.cloud_configs[var.cloud_provider]
}

# Control plane user data template
data "template_file" "control_plane_init" {
  template = file("${path.module}/templates/control-plane-init.sh.tftpl")
  
  vars = {
    cluster_name        = var.cluster_name
    kubernetes_version  = var.kubernetes_version
    pod_cidr           = var.pod_cidr
    service_cidr       = var.service_cidr
    kubeadm_token      = local.kubeadm_token
    certificate_key    = local.certificate_key
    cloud_provider     = local.cloud_config.cloud_provider
    cloud_config_path  = local.cloud_config.cloud_config_path
  }
}

# Worker node user data template
data "template_file" "worker_join" {
  template = file("${path.module}/templates/worker-join.sh.tftpl")
  
  vars = {
    cluster_name       = var.cluster_name
    kubernetes_version = var.kubernetes_version
    kubeadm_token      = local.kubeadm_token
    cloud_provider     = local.cloud_config.cloud_provider
    cloud_config_path  = local.cloud_config.cloud_config_path
  }
}

# Outputs for other modules
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
  value       = data.template_file.control_plane_init.rendered
}

output "worker_user_data" {
  description = "User data for worker node joining"
  value       = data.template_file.worker_join.rendered
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