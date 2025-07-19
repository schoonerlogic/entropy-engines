# AWS Kubernetes Controller Module Variables
variable "base_ami_id" {
  description = "Used for all current cpu instances"
  type        = string
}

variable "environment" {
  description = "Stage of developement"
  type        = string
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
    availability_zones        = optional(list(string), null) # Will use data source if null
    public_subnet_count       = optional(number, 2)
    private_subnet_count      = optional(number, 3)
    subnet_ids                = list(string)
    iam_policy_version        = optional(string, "v1")
    iam_instance_profile_name = optional(string, "ec2_role_name")
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

    ssm_join_command_path    = optional(string, null)
    ssm_certificate_key_path = optional(string, null)
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
}

