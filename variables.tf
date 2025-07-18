# Main  Variables
variable "bootstrap_script" {
  description = "Loading user_data for instance"
  type        = list(string)
}

# Core Configuration Object
variable "core_config" {
  description = "Core configuration settings"
  type = object({
    aws_region  = optional(string, "us-east-1")
    environment = optional(string, "dev")
    project     = optional(string, "agentic-platform")
    vpc_name    = string
  })
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
    subnet_ids           = list(string)
    iam_policy_version   = optional(string, "v1")
  })
}

# Security Configuration Object
variable "security_config" {
  description = "Security configuration settings"
  type = object({
    ssh_allowed_cidrs     = optional(list(string), []) # Empty by default for security
    bastion_allowed_cidrs = optional(list(string), []) # Empty by default for security
    enable_bastion_host   = optional(bool, true)
    bastion_instance_type = optional(string, "t3.micro")
    bastion_host          = string
    bastion_user          = optional(string, "ubuntu")
    ssh_public_key_path   = optional(string, "~/.ssh/lwpub.pem")
    ssh_private_key_path  = optional(string, "~/.ssh/lw.pem")
    ssh_key_name          = string
    security_group_ids    = list(string)
  })
}

# NAT Configuration Object
variable "nat_config" {
  description = "NAT configuration settings"
  type = object({
    nat_type           = optional(string, "gateway")
    single_nat_gateway = optional(bool, true)
  })

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

    k8s_user               = string
    k8s_major_minor_stream = string
    k8s_full_patch_version = string
    k8s_apt_package_suffix = string

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
}

# Instance Configuration Object
variable "instance_config" {
  description = "Instance configuration settings"
  type = object({
    ami_architecture         = optional(string, "arm64")
    ubuntu_version           = optional(string, "22.04")
    enable_volume_encryption = optional(bool, true)
    kms_key_id               = optional(string, null) # Use AWS managed key if null
    instance_type            = list(string)
    on_demand_count          = optional(number, 0)
    spot_count               = optional(number, 0)
  })
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

variable "k8s_config" {
  description = "Kubernetes settings"
  type = object({
    ssh_private_key_path   = optional(string, "~/.ssh/lw.pem")
    ssh_public_key_path    = optional(string, "~/.ssh/lw.pem.pub")
    k8s_user               = optional(string, "ubuntu")
    k8s_major_minor_stream = optional(string, "1.33.3")
    k8s_full_patch_version = optional(string, "1.33.0")
    k8s_apt_package_suffix = optional(string, "-00")
  })
}

variable "k8s_control_plane_config" {
  description = "Kubernetes settings"
  type = object({
    instance_count      = optional(number, 1)
    instance_type       = optional(string, "t4g.medium")
    on_demand_count     = optional(number, 0)
    spot_count          = optional(number, 0)
    spot_instance_types = optional(string, "m7g.medium")
  })
}

variable "k8s_cpu_worker_config" {
  description = "Kubernetes settings"
  type = object({
    instance_count     = optional(number, 1)
    instance_type      = optional(string, "t4g.medium")
    on_demand_count    = optional(number, 0)
    spot_count         = optional(number, 0)
    spot_instance_type = optional(string, "m7g.medium")
  })
}

variable "k8s_gpu_worker_config" {
  description = "Kubernetes settings"
  type = object({
    instance_count     = optional(number, 1)
    instance_type      = optional(string, "t4g.medium")
    on_demand_count    = optional(number, 0)
    spot_count         = optional(number, 0)
    spot_instance_type = optional(string, "m7g.medium")
  })
}
