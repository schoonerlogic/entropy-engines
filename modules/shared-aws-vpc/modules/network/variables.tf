# Network Module Variables - Enhanced for Kubernetes

variable "region" {
  description = "AWS region"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "vpc_name" {
  description = "Name for the VPC"
  type        = string
}

variable "project" {
  description = "Project name used for resource naming"
  type        = string
}

variable "nat_type" {
  description = "Type of NAT to use: gateway, instance, or none"
  type        = string
  validation {
    condition     = contains(["gateway", "instance", "none"], var.nat_type)
    error_message = "NAT type must be one of: gateway, instance, none."
  }
}

variable "ssh_key_name" {
  description = "SSH key name for instances"
  type        = string
}

variable "bastion_type" {
  description = "Instance type for bastion host"
  type        = string
  default     = "t3.micro"
}

variable "k8s_api_server_port" {
  description = "Port the Kubernetes API server listens on"
  type        = number
  default     = 6443
}

# New cloud-agnostic variables
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "kubernetes_cidrs" {
  description = "Kubernetes networking CIDRs"
  type = object({
    pod_cidr     = string
    service_cidr = string
  })
  default = {
    pod_cidr     = "10.244.0.0/16"
    service_cidr = "10.96.0.0/12"
  }
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = null
}

variable "public_subnet_count" {
  description = "Number of public subnets to create"
  type        = number
  default     = 2
}

variable "private_subnet_count" {
  description = "Number of private subnets to create"
  type        = number
  default     = 3
}

variable "ssh_allowed_cidrs" {
  description = "List of CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = []
}

variable "bastion_allowed_cidrs" {
  description = "List of CIDR blocks allowed for bastion host access"
  type        = list(string)
  default     = []
}

variable "enable_bastion_host" {
  description = "Enable creation of bastion host"
  type        = bool
  default     = true
}

variable "enable_kubernetes_tags" {
  description = "Add Kubernetes-specific tags to subnets"
  type        = bool
  default     = true
}

variable "kubernetes_cluster_name" {
  description = "Name of the Kubernetes cluster for tagging"
  type        = string
  default     = null
}

variable "enable_nats_messaging" {
  description = "Enable NATS messaging security groups"
  type        = bool
  default     = true
}

variable "nats_ports" {
  description = "NATS messaging ports"
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

variable "enable_gpu_nodes" {
  description = "Enable GPU-specific security groups"
  type        = bool
  default     = true
}

variable "instance_ami_architecture" {
  description = "Architecture for AMI selection (arm64 or x86_64)"
  type        = string
  default     = "arm64"
}

variable "ubuntu_version" {
  description = "Ubuntu version for AMI selection"
  type        = string
  default     = "22.04"
}

variable "enable_volume_encryption" {
  description = "Enable encryption for EBS volumes"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for EBS encryption"
  type        = string
  default     = null
}

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

# Legacy variables for backward compatibility
variable "tooling_sg_name" {
  description = "Legacy tooling security group name"
  type        = string
  default     = "tooling-sg"
}

variable "bastion_allowed_ssh_cidrs" {
  description = "Legacy CIDR blocks allowed for bastion host access (deprecated, use bastion_allowed_cidrs)"
  type        = list(string)
  default     = []
}