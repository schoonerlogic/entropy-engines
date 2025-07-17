# Cloud-Agnostic AWS VPC Module Variables
# Enhanced for Kubernetes and multi-cloud compatibility
# Organized into logical groups for better maintainability

# Core Configuration Object
variable "core_config" {
  description = "Core configuration settings"
  type = object({
    aws_region  = optional(string, "us-east-1")
    environment = optional(string, "dev")
    project     = optional(string, "agentic-platform")
    vpc_name    = string
  })

  validation {
    condition     = contains(["dev", "staging", "prod"], var.core_config.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Network Configuration Object
variable "network_config" {
  description = "Network configuration settings"
  type = object({
    vpc_cidr = optional(string, "10.0.0.0/16")
    kubernetes_cidrs = optional(object({
      pod_cidr     = string
      service_cidr = string
      }), {
      pod_cidr     = "10.244.0.0/16"
      service_cidr = "10.96.0.0/12"
    })
    availability_zones   = optional(list(string), null) # Will use data source if null
    public_subnet_count  = optional(number, 2)
    private_subnet_count = optional(number, 3)
  })
  default = {}
}

# Security Configuration Object
variable "security_config" {
  description = "Security configuration settings"
  type = object({
    ssh_allowed_cidrs     = optional(list(string), []) # Empty by default for security
    bastion_allowed_cidrs = optional(list(string), []) # Empty by default for security
    enable_bastion_host   = optional(bool, true)
    bastion_instance_type = optional(string, "t3.micro")
    ssh_key_name          = string
  })
}

# NAT Configuration Object
variable "nat_config" {
  description = "NAT configuration settings"
  type = object({
    nat_type           = optional(string, "gateway")
    single_nat_gateway = optional(bool, true)
  })
  default = {}

  validation {
    condition     = contains(["gateway", "instance", "none"], var.nat_config.nat_type)
    error_message = "NAT type must be one of: gateway, instance, none."
  }
}

# Kubernetes Configuration Object
variable "kubernetes_config" {
  description = "Kubernetes integration settings"
  type = object({
    enable_kubernetes_tags = optional(bool, true)
    cluster_name           = optional(string, null) # Will use project name if null
    enable_nats_messaging  = optional(bool, true)
    nats_ports = optional(object({
      client     = number
      cluster    = number
      leafnode   = number
      monitoring = number
      }), {
      client     = 4222
      cluster    = 6222
      leafnode   = 7422
      monitoring = 8222
    })
    enable_gpu_nodes = optional(bool, true)
  })
  default = {}
}

# Instance Configuration Object
variable "instance_config" {
  description = "Instance configuration settings"
  type = object({
    ami_architecture         = optional(string, "arm64")
    ubuntu_version           = optional(string, "22.04")
    enable_volume_encryption = optional(bool, true)
    kms_key_id               = optional(string, null) # Use AWS managed key if null
  })
  default = {}
}

# Cost Optimization Object
variable "cost_optimization" {
  description = "Cost optimization settings"
  type = object({
    enable_spot_instances = optional(bool, true)
    enable_vpc_endpoints  = optional(bool, true)
  })
  default = {}
}

# Legacy Configuration Object (optional for backward compatibility)
variable "legacy_config" {
  description = "Legacy configuration for backward compatibility"
  type = object({
    bastion_cidr         = optional(string, "0.0.0.0/0")
    ssh_public_key_path  = optional(string, "~/.ssh/lwpub.pem")
    ssh_private_key_path = optional(string, "~/.ssh/lw.pem")
    github_owner         = optional(string, "")
    github_token         = optional(string, "")
  })
  default = {}

  sensitive = true # Mark as sensitive due to tokens
}
