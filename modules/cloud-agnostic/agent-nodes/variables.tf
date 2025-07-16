# Agent Nodes Module Variables

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
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

variable "cpu_worker_count" {
  description = "Number of CPU worker nodes"
  type        = number
  default     = 2
}

variable "cpu_worker_instance_type" {
  description = "Instance type for CPU workers"
  type        = string
  default     = "m7g.large"
}

variable "gpu_worker_count" {
  description = "Number of GPU worker nodes"
  type        = number
  default     = 1
}

variable "gpu_worker_instance_type" {
  description = "Instance type for GPU workers"
  type        = string
  default     = "g5g.xlarge"
}

variable "ssh_key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
}

variable "kubeadm_token" {
  description = "Kubeadm token for joining nodes"
  type        = string
  sensitive   = true
}

variable "certificate_key" {
  description = "Certificate key for joining control plane nodes"
  type        = string
  sensitive   = true
}

variable "control_plane_user_data" {
  description = "User data for control plane initialization"
  type        = string
}

variable "worker_user_data" {
  description = "User data for worker node joining"
  type        = string
}