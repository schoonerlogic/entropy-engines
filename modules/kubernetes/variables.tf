# ./modules/kubernetes/variables.tf

#===============================================================================
# Core Configuration - ADD THIS
#===============================================================================
variable "core_config" {
  description = "Core configuration settings"
  type = object({
    aws_region  = string
    environment = string
    project     = string
    vpc_name    = string
  })
}

variable "cluster_name" {
  description = "The name of the Kubernetes cluster"
  type        = string
  default     = null # Allow this to be optional since it can come from kubernetes_config
}

variable "aws_region" {
  description = "AWS region for deployment"
  type = object({
    name = string
  })
}

variable "log_level" {
  description = "Log verbosity level"
  type        = string
  default     = "INFO"
}

variable "k8s_scripts_bucket_name" {
  description = "Name of the S3 bucket containing setup scripts"
  type        = string
}

variable "aws_ami" {
  description = "Base AMI ID to use for worker instances"
  type        = string
}

#===============================================================================
# Security Configuration - ADD THIS
#===============================================================================
variable "security_config" {
  description = "Security configuration settings"
  type = object({
    environment           = string
    ssh_allowed_cidrs     = optional(list(string), [])
    bastion_allowed_cidrs = optional(list(string), [])
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

#===============================================================================
# Network Variables - ADD THESE
#===============================================================================
variable "pod_cidr_block" {
  description = "CIDR block for Kubernetes pods"
  type        = string
}

variable "service_cidr_block" {
  description = "CIDR block for Kubernetes services"
  type        = string
}


# Role names
variable "control_plane_role_name" {
  description = "Name of the IAM role for the control plane"
  type        = string
  default     = null
}

variable "worker_role_name" {
  description = "Name of the IAM role for worker nodes"
  type        = string
  default     = null
}

variable "gpu_worker_role_name" {
  description = "Name of the IAM role for GPU worker nodes"
  type        = string
  default     = null
}

#===============================================================================
# Kubernetes Configuration
#===============================================================================
variable "kubernetes_config" {
  description = "Kubernetes integration settings"
  type = object({
    enable_kubernetes_tags = optional(bool, true)
    cluster_name           = optional(string, null)
    enable_nats_messaging  = optional(bool, true)
    ssh_private_key_path   = optional(string, "~/.ssh/lw.pem")
    ssh_public_key_path    = optional(string, "~/.ssh/lw.pem.pub")
    k8s_user               = optional(string, "ubuntu")
    k8s_major_minor_stream = optional(string, "1.33.3")
    k8s_full_patch_version = optional(string, "1.33.0")
    k8s_apt_package_suffix = optional(string, "-0.0")

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

    ssm_join = optional(object({
      ssm_join_command_path    = string
      ssm_certificate_key_path = string
      }), {
      ssm_join_command_path    = ""
      ssm_certificate_key_path = ""
    })
  })
}

variable "network_config" {
  type = object({
    k8s_scripts_bucket_name = optional(string, "k8s-scripts-bucket")
    k8s_scripts_bucket      = optional(string, null)
    vpc_cidr                = optional(string, "10.0.0.0/16")
    skip_bucket_validation  = optional(bool, false)
    bucket_retry_timeout    = optional(number, 300)

    kubernetes_cidrs = optional(object({
      pod_cidr     = string
      service_cidr = string
      }), {
      pod_cidr     = "10.244.0.0/16"
      service_cidr = "10.96.0.0/12"
    })

    cluster_dns_ip       = optional(string, "10.244.0.0/16")
    availability_zones   = optional(list(string), null)
    public_subnet_count  = optional(number, 2)
    private_subnet_count = optional(number, 4)
    vpc_id               = string
    subnet_ids           = list(string)
    iam_policy_version   = optional(string, "v1")

    private_subnet_ids              = optional(list(string), [])
    control_plane_security_group_id = optional(list(string), [])
  })

  description = <<-EOT
  Configuration for Kubernetes resources:
  - k8s_scripts_bucket_name: Name for new bucket (auto-appends random suffix if not provided)
  - k8s_scripts_bucket: Existing bucket ARN/name (overrides bucket_name if set)
  - skip_bucket_validation: Bypass bucket readiness checks (not recommended)
  - bucket_retry_timeout: Timeout in seconds for bucket validation
  EOT
}

#===============================================================================
# Base Instance Configuration
#===============================================================================
variable "instance_config" {
  description = "Base instance configuration settings for all instance types"
  type = object({
    ami_architecture         = optional(string, "arm64")
    ubuntu_version           = optional(string, "22.04")
    enable_volume_encryption = optional(bool, true)
    kms_key_id               = optional(string, null)

    default_block_device_mappings = optional(list(object({
      device_name           = string
      volume_size           = number
      volume_type           = optional(string, "gp3")
      delete_on_termination = optional(bool, true)
      encrypted             = optional(bool, true)
      iops                  = optional(number, null)
      throughput            = optional(number, null)
      kms_key_id            = optional(string, null)
      })), [
      {
        device_name           = "/dev/sda1"
        volume_size           = 30
        volume_type           = "gp3"
        delete_on_termination = true
        encrypted             = true
      }
    ])
  })
}

#===============================================================================
# IAM Configuration
#===============================================================================
variable "iam_config" {
  description = "IAM configuration settings"
  type = object({
    control_plane_role_name = optional(string, "control-plane-role-name")
    worker_role_name        = optional(string, "cpu-worker-role-name")
    gpu_worker_role_name    = optional(string, "gpu-worker-role-name")
    # ADD MISSING FIELD
    cpu_worker_role_name = optional(string, null)
  })
  default = {}
}

#===============================================================================
# Control Plane Configuration
#===============================================================================
variable "k8s_control_plane_config" {
  description = "Kubernetes control plane configuration"
  type = object({
    instance_count      = optional(number, 1)
    instance_type       = optional(string, "t4g.medium")
    on_demand_count     = optional(number, 1)
    spot_count          = optional(number, 0)
    spot_instance_types = optional(list(string), [])
    # ADD MISSING FIELD
    instance_types = optional(list(string), ["t4g.medium"])

    block_device_mappings = optional(list(object({
      device_name           = string
      volume_size           = number
      volume_type           = optional(string, "gp3")
      delete_on_termination = optional(bool, true)
      encrypted             = optional(bool, true)
      iops                  = optional(number, null)
      throughput            = optional(number, null)
      kms_key_id            = optional(string, null)
    })), null)
  })
  default = {}
}

#===============================================================================
# Worker Configuration
#===============================================================================
variable "worker_config" {
  description = "Consolidated worker node configuration settings"
  type = object({
    instance_types            = optional(list(string), [])
    use_instance_requirements = optional(bool, false)

    instance_requirements = optional(object({
      vcpu_count = object({
        min = number
        max = number
      })
      memory_mib = object({
        min = number
        max = number
      })
      cpu_architectures             = optional(list(string), ["arm_64"])
      excluded_instance_generations = optional(list(string), ["1", "2", "3"])
      excluded_instance_types       = optional(list(string), [])
      allowed_instance_types        = optional(list(string), [])
      instance_categories           = optional(list(string), [])
      burstable_performance         = optional(string, "included")
      bare_metal                    = optional(string, "excluded")
      require_hibernate_support     = optional(bool, false)
      local_storage                 = optional(string, "included")
      local_storage_types           = optional(list(string), ["ssd"])
      total_local_storage_gb = optional(object({
        min = optional(number, null)
        max = optional(number, null)
      }), null)
      network_interface_count = optional(object({
        min = optional(number, null)
        max = optional(number, null)
      }), null)
      network_bandwidth_gbps = optional(object({
        min = optional(number, null)
        max = optional(number, null)
      }), null)
      baseline_ebs_bandwidth_mbps = optional(object({
        min = optional(number, null)
        max = optional(number, null)
      }), null)
      accelerator_count = optional(object({
        min = optional(number, null)
        max = optional(number, null)
      }), null)
      accelerator_manufacturers = optional(list(string), [])
      accelerator_names         = optional(list(string), [])
      accelerator_types         = optional(list(string), [])
    }), null)

    cpu_workers = optional(object({
      on_demand_count = optional(number, 0)
      spot_count      = optional(number, 0)
    }), { on_demand_count = 0, spot_count = 0 })

    gpu_workers = optional(object({
      on_demand_count = optional(number, 0)
      spot_count      = optional(number, 0)
    }), { on_demand_count = 0, spot_count = 0 })

    asg_config = optional(object({
      min_size                  = optional(number, null)
      max_size                  = optional(number, null)
      health_check_type         = optional(string, "EC2")
      health_check_grace_period = optional(number, 300)
      min_healthy_percentage    = optional(number, 50)
      instance_warmup           = optional(number, 300)
      capacity_timeout          = optional(string, "15m")
      instance_refresh_triggers = optional(list(string), ["tag"])
    }), {})

    spot_config = optional(object({
      spot_allocation_strategy = optional(string, "capacity-optimized")
      spot_instance_pools      = optional(number, 2)
    }), {})

    worker_storage_overrides = optional(object({
      block_device_mappings = optional(list(object({
        device_name           = string
        volume_size           = number
        volume_type           = optional(string, "gp3")
        delete_on_termination = optional(bool, true)
        encrypted             = optional(bool, true)
        iops                  = optional(number, null)
        throughput            = optional(number, null)
        kms_key_id            = optional(string, null)
      })), null)
    }), {})

    gpu_config = optional(object({
      gpu_type       = optional(string, "nvidia")
      gpu_memory_min = optional(number, null)

      gpu_asg_overrides = optional(object({
        health_check_grace_period = optional(number, 600)
        min_healthy_percentage    = optional(number, 25)
        instance_warmup           = optional(number, 600)
        spot_instance_pools       = optional(number, 2)
      }), {})

      gpu_storage_overrides = optional(object({
        block_device_mappings = optional(list(object({
          device_name           = string
          volume_size           = number
          volume_type           = optional(string, "gp3")
          delete_on_termination = optional(bool, true)
          encrypted             = optional(bool, true)
          iops                  = optional(number, null)
          throughput            = optional(number, null)
          kms_key_id            = optional(string, null)
          })), [
          {
            device_name           = "/dev/sda1"
            volume_size           = 100
            volume_type           = "gp3"
            delete_on_termination = true
            encrypted             = true
            throughput            = 250
          }
        ])
      }), {})
    }), {})

    additional_tags = optional(map(string), {})
  })
  default = {}
}
