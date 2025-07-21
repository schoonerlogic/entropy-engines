# modules/infrastructure/cloud-specific/aws/variables.tf
# Updated to use individual variables instead of config objects

#===============================================================================
# Core Configuration Variables
#===============================================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "agentic-platform"
}

variable "vpc_name" {
  description = "VPC name"
  type        = string
}

#===============================================================================
# IAM Configuration Variables
#===============================================================================

variable "control_plane_role_name" {
  description = "Name of the control plane IAM role"
  type        = string
  default     = null
}

variable "worker_role_name" {
  description = "Name of the worker IAM role"
  type        = string
  default     = null
}

variable "gpu_worker_role_name" {
  description = "Name of the GPU worker IAM role"
  type        = string
  default     = null
}

#===============================================================================
# Network Configuration Variables
#===============================================================================

variable "base_aws_ami" {
  description = "Base AWS AMI ID"
  type        = string
}

variable "gpu_aws_ami" {
  description = "GPU-enabled AWS AMI ID"
  type        = string
  default     = null
}

variable "bootstrap_bucket_name" {
  description = "S3 bucket name for worker bootstrap"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "kubernetes_cidrs" {
  description = "Kubernetes CIDR blocks"
  type = object({
    pod_cidr     = string
    service_cidr = string
  })
  default = {
    pod_cidr     = "10.244.0.0/16"
    service_cidr = "10.96.0.0/12"
  }
}

variable "cluster_dns_ip" {
  description = "Cluster DNS IP address"
  type        = string
  default     = null
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = null
}

variable "public_subnet_count" {
  description = "Number of public subnets"
  type        = number
  default     = 2
}

variable "private_subnet_count" {
  description = "Number of private subnets"
  type        = number
  default     = 3
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
}

variable "iam_policy_version" {
  description = "IAM policy version"
  type        = string
  default     = "v1"
}

#===============================================================================
# NAT Configuration Variables
#===============================================================================

variable "nat_type" {
  description = "Type of NAT (gateway, instance, none)"
  type        = string
  default     = "gateway"

  validation {
    condition     = contains(["gateway", "instance", "none"], var.nat_type)
    error_message = "NAT type must be one of: gateway, instance, none."
  }
}

variable "single_nat_gateway" {
  description = "Use single NAT gateway"
  type        = bool
  default     = true
}

#===============================================================================
# Security Configuration Variables
#===============================================================================

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = []
}

variable "bastion_allowed_cidrs" {
  description = "CIDR blocks allowed for bastion access"
  type        = list(string)
  default     = []
}

variable "enable_bastion_host" {
  description = "Enable bastion host"
  type        = bool
  default     = true
}

variable "bastion_instance_type" {
  description = "Bastion host instance type"
  type        = string
  default     = "t3.micro"
}

variable "bastion_host" {
  description = "Bastion host IP or hostname"
  type        = string
}

variable "bastion_user" {
  description = "Bastion host username"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key"
  type        = string
  default     = "~/.ssh/lwpub.pem"
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key"
  type        = string
  default     = "~/.ssh/lw.pem"
}

variable "ssh_key_name" {
  description = "SSH key name"
  type        = string
}

variable "security_group_ids" {
  description = "List of security group IDs"
  type        = list(string)
}

#===============================================================================
# Kubernetes Configuration Variables
#===============================================================================

variable "enable_kubernetes_tags" {
  description = "Enable Kubernetes tags"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Kubernetes cluster name"
  type        = string
  default     = null
}

variable "enable_nats_messaging" {
  description = "Enable NATS messaging"
  type        = bool
  default     = true
}

variable "k8s_user" {
  description = "Kubernetes user"
  type        = string
}

variable "k8s_major_minor_stream" {
  description = "Kubernetes major.minor version stream"
  type        = string
}

variable "k8s_full_patch_version" {
  description = "Kubernetes full patch version"
  type        = string
}

variable "k8s_apt_package_suffix" {
  description = "Kubernetes APT package suffix"
  type        = string
}

variable "enable_gpu_nodes" {
  description = "Enable GPU nodes"
  type        = bool
  default     = true
}

variable "nats_ports" {
  description = "NATS port configuration"
  type = object({
    client     = number
    cluster    = number
    leafnode   = number
    monitoring = number
  })
  default = {
    client     = 4222
    cluster    = 6222
    leafnode   = 7422
    monitoring = 8222
  }
}

#===============================================================================
# Cost Optimization Variables
#===============================================================================

variable "enable_spot_instances" {
  description = "Enable spot instances for cost optimization"
  type        = bool
  default     = true
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for cost optimization"
  type        = bool
  default     = true
}
