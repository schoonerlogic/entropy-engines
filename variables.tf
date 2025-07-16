# Main Infrastructure Variables

# Core Configuration
variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "agentic-platform"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Additional tags to apply to all AWS resources"
  type        = map(string)
  default     = {}
}

# AWS Configuration
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "ssh_key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "bastion_allowed_cidrs" {
  description = "CIDR blocks allowed for bastion access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Networking Configuration
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "pod_cidr" {
  description = "Pod CIDR range"
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "Service CIDR range"
  type        = string
  default     = "10.96.0.0/12"
}

# Kubernetes Configuration
variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.29.0"
}

# Control Plane Configuration
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

# CPU Worker Configuration
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

# GPU Worker Configuration
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

# NATS Configuration
variable "nats_version" {
  description = "NATS server version"
  type        = string
  default     = "2.10.0"
}

variable "nats_instance_type" {
  description = "Instance type for NATS servers"
  type        = string
  default     = "t4g.small"
}

# Cost Optimization
variable "single_nat_gateway" {
  description = "Use single NAT gateway for cost optimization"
  type        = bool
  default     = true
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for cost optimization"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_bastion_host" {
  description = "Enable creation of bastion host"
  type        = bool
  default     = false
}

variable "enable_volume_encryption" {
  description = "Enable EBS volume encryption"
  type        = bool
  default     = true
}