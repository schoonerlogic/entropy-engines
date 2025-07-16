# Cloud-Agnostic AWS VPC Module Variables
# Enhanced for Kubernetes and multi-cloud compatibility

# Core Configuration
variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment level (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project" {
  description = "Project name used for resource naming"
  type        = string
  default     = "agentic-platform"
}

variable "vpc_name" {
  description = "Name of VPC"
  type        = string
}

# Network Configuration
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
  default     = null # Will use data source if null
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

# Security Configuration
variable "ssh_allowed_cidrs" {
  description = "List of CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = [] # Empty by default for security
}

variable "bastion_allowed_cidrs" {
  description = "List of CIDR blocks allowed for bastion host access"
  type        = list(string)
  default     = [] # Empty by default for security
}

variable "enable_bastion_host" {
  description = "Enable creation of bastion host"
  type        = bool
  default     = true
}

variable "bastion_instance_type" {
  description = "Instance type for bastion host"
  type        = string
  default     = "t3.micro"
}

# NAT Configuration
variable "nat_type" {
  description = "Type of NAT to use: gateway, instance, or none"
  type        = string
  default     = "gateway"
  validation {
    condition     = contains(["gateway", "instance", "none"], var.nat_type)
    error_message = "NAT type must be one of: gateway, instance, none."
  }
}

variable "single_nat_gateway" {
  description = "Use single NAT gateway for cost optimization"
  type        = bool
  default     = true
}

# Kubernetes Integration
variable "enable_kubernetes_tags" {
  description = "Add Kubernetes-specific tags to subnets"
  type        = bool
  default     = true
}

variable "kubernetes_cluster_name" {
  description = "Name of the Kubernetes cluster for tagging"
  type        = string
  default     = null # Will use project name if null
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
  description = "Enable GPU-specific security groups and configurations"
  type        = bool
  default     = true
}

# Instance Configuration
variable "ssh_key_name" {
  description = "Name of the SSH key pair"
  type        = string
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
  default     = null # Use AWS managed key if null
}

# Cost Optimization
variable "enable_spot_instances" {
  description = "Enable spot instance support"
  type        = bool
  default     = true
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for cost optimization"
  type        = bool
  default     = true
}

# Legacy variables (for backward compatibility)
variable "bastion_cidr" {
  description = "Legacy CIDR block for bastion host access (deprecated, use bastion_allowed_cidrs)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key (legacy)"
  type        = string
  default     = "~/.ssh/lwpub.pem"
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key (legacy)"
  type        = string
  default     = "~/.ssh/lw.pem"
}

variable "github_owner" {
  description = "GitOps repository owner (legacy)"
  type        = string
  default     = ""
}

variable "github_token" {
  description = "Github PAT (legacy)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "onepassword_token" {
  description = "1Password token for Terraform (legacy)"
  type        = string
  sensitive   = true
  default     = ""
}