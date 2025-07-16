# Kubernetes Cluster Module Variables

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
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
    region             = string
    availability_zones = list(string)
    instance_profile   = string
    security_group_ids = list(string)
    subnet_ids         = list(string)
    vpc_id             = string
  })
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.29.0"
}

variable "control_plane_private_ip" {
  description = "Private IP address of the control plane node"
  type        = string
}

variable "discovery_token_ca_cert_hash" {
  description = "CA certificate hash for kubeadm discovery"
  type        = string
  default     = "sha256:399a2eb369c7bd7b1f84a77d68e005a933eb4ee7e05db12f23fc69535d598e66"
}