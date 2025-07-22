# root/variables.tf - Complete consolidated variable structure

#===============================================================================
# Core Configuration
#===============================================================================

variable "core_config" {
  description = "Core configuration settings"
  type = object({
    aws_region  = optional(string, "us-east-1")
    environment = optional(string, "dev")
    project     = optional(string, "agentic-platform")
    vpc_name    = string
  })
}

#===============================================================================
# Network Configuration
#===============================================================================

variable "network_config" {
  description = "Network configuration settings"
  type = object({
    base_aws_ami          = optional(string, null)
    gpu_aws_ami           = optional(string, null) # Separate GPU AMI with NVIDIA drivers
    bootstrap_bucket_name = optional(string, "k8s-worker-bootstrap-bucket")
    vpc_cidr              = optional(string, "10.0.0.0/16")

    kubernetes_cidrs = optional(object({
      pod_cidr     = string
      service_cidr = string
      }), {
      pod_cidr     = "10.244.0.0/16"
      service_cidr = "10.96.0.0/12"
    })

    cluster_dns_ip       = optional(string, "10.244.0.0/16")
    availability_zones   = optional(list(string), null) # Will use data source if null
    public_subnet_count  = optional(number, 2)
    private_subnet_count = optional(number, 3)
    subnet_ids           = list(string)
    iam_policy_version   = optional(string, "v1")
  })
}

#===============================================================================
# Security Configuration
#===============================================================================

variable "security_config" {
  description = "Security configuration settings"
  type = object({
    environment           = string
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

#===============================================================================
# Kubernetes Configuration
#===============================================================================

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
    enable_gpu_nodes       = optional(bool, true)

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
  })
}

#===============================================================================
# Base Instance Configuration (applies to ALL instances)
#===============================================================================

variable "instance_config" {
  description = "Base instance configuration settings for all instance types"
  type = object({
    ami_architecture         = optional(string, "arm64")
    ubuntu_version           = optional(string, "22.04")
    enable_volume_encryption = optional(bool, true)
    kms_key_id               = optional(string, null) # Use AWS managed key if null

    # Default block device mappings (used by all instances unless overridden)
    default_block_device_mappings = optional(list(object({
      device_name           = string
      volume_size           = number
      volume_type           = optional(string, "gp3")
      delete_on_termination = optional(bool, true)
      encrypted             = optional(bool, true)
      iops                  = optional(number, null) # For io1/io2/gp3 volumes
      throughput            = optional(number, null) # For gp3 volumes only
      kms_key_id            = optional(string, null) # Override instance-level KMS key
      })), [
      {
        device_name           = "/dev/sda1"
        volume_size           = 30 # Minimal since you use NVMe ephemeral
        volume_type           = "gp3"
        delete_on_termination = true
        encrypted             = true
      }
    ])
  })
}

#===============================================================================
# Consolidated Worker Configuration (replaces separate CPU/GPU configs)
#===============================================================================

variable "worker_config" {
  description = "Consolidated worker node configuration settings"
  type = object({

    #---------------------------------------------------------------------------
    # Instance Configuration (shared by both worker types)
    #---------------------------------------------------------------------------

    # Traditional instance types (alternative to instance requirements)
    instance_types            = optional(list(string), [])
    use_instance_requirements = optional(bool, false)

    # Instance requirements (comprehensive object for both CPU and GPU)
    instance_requirements = optional(object({
      vcpu_count = object({
        min = number
        max = number
      })
      memory_mib = object({
        min = number
        max = number
      })
      cpu_architectures             = optional(list(string), ["x86_64"])
      excluded_instance_generations = optional(list(string), ["1", "2", "3"])
      excluded_instance_types       = optional(list(string), [])
      allowed_instance_types        = optional(list(string), [])
      instance_categories           = optional(list(string), [])
      burstable_performance         = optional(string, "included")
      bare_metal                    = optional(string, "excluded")
      require_hibernate_support     = optional(bool, false)

      # Storage requirements
      local_storage       = optional(string, "included") # For NVMe
      local_storage_types = optional(list(string), ["ssd"])
      total_local_storage_gb = optional(object({
        min = optional(number, null)
        max = optional(number, null)
      }), null)

      # Network performance
      network_interface_count = optional(object({
        min = optional(number, null)
        max = optional(number, null)
      }), null)
      network_bandwidth_gbps = optional(object({
        min = optional(number, null)
        max = optional(number, null)
      }), null)

      # EBS bandwidth
      baseline_ebs_bandwidth_mbps = optional(object({
        min = optional(number, null)
        max = optional(number, null)
      }), null)

      # GPU-specific requirements (only used by GPU workers)
      accelerator_count = optional(object({
        min = optional(number, null)
        max = optional(number, null)
      }), null)
      accelerator_manufacturers = optional(list(string), [])
      accelerator_names         = optional(list(string), [])
      accelerator_types         = optional(list(string), [])
    }), null)

    #---------------------------------------------------------------------------
    # Instance Counts (per worker type)
    #---------------------------------------------------------------------------

    cpu_workers = optional(object({
      on_demand_count = optional(number, 0)
      spot_count      = optional(number, 0)
    }), { on_demand_count = 0, spot_count = 0 })

    gpu_workers = optional(object({
      on_demand_count = optional(number, 0)
      spot_count      = optional(number, 0)
    }), { on_demand_count = 0, spot_count = 0 })

    #---------------------------------------------------------------------------
    # Auto Scaling Group Configuration (shared defaults)
    #---------------------------------------------------------------------------

    asg_config = optional(object({
      min_size                  = optional(number, null) # defaults to total count
      max_size                  = optional(number, null) # defaults to total count
      health_check_type         = optional(string, "EC2")
      health_check_grace_period = optional(number, 300)
      min_healthy_percentage    = optional(number, 50)
      instance_warmup           = optional(number, 300)
      capacity_timeout          = optional(string, "15m")
      instance_refresh_triggers = optional(list(string), ["tag"])
    }), {})

    #---------------------------------------------------------------------------
    # Spot Configuration (shared defaults)
    #---------------------------------------------------------------------------

    spot_config = optional(object({
      spot_allocation_strategy = optional(string, "capacity-optimized")
      spot_instance_pools      = optional(number, 2)
    }), {})

    #---------------------------------------------------------------------------
    # Worker Storage Overrides (overrides instance_config defaults for workers)
    #---------------------------------------------------------------------------

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
      })), null) # null = use instance_config defaults
    }), {})

    #---------------------------------------------------------------------------
    # GPU-specific Configuration (only used by GPU workers)
    #---------------------------------------------------------------------------

    gpu_config = optional(object({
      # GPU identification
      gpu_type       = optional(string, "nvidia")
      gpu_memory_min = optional(number, null) # Minimum GPU memory in GiB

      # GPU-specific ASG overrides
      gpu_asg_overrides = optional(object({
        health_check_grace_period = optional(number, 600) # Longer for GPU driver initialization
        min_healthy_percentage    = optional(number, 25)  # Lower due to high cost per instance
        instance_warmup           = optional(number, 600) # Time for GPU drivers to load
        spot_instance_pools       = optional(number, 2)   # Fewer pools but more predictable
      }), {})

      # GPU-specific storage overrides (typically larger than CPU workers)
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
            volume_size           = 100 # Larger for GPU drivers, CUDA, ML frameworks
            volume_type           = "gp3"
            delete_on_termination = true
            encrypted             = true
            throughput            = 250 # Higher throughput for faster boot
          }
        ])
      }), {})
    }), {})

    #---------------------------------------------------------------------------
    # Additional Tags (applied to all worker resources)
    #---------------------------------------------------------------------------

    additional_tags = optional(map(string), {})
  })
  default = {}

  # Validations inside the worker_config variable block
  # validation {
  #   condition = (
  #     self.use_instance_requirements == true ?
  #     length(self.instance_types) == 0 :
  #     true
  #   )
  #   error_message = "When use_instance_requirements is true, instance_types list should be empty."
  # }
  #
  # validation {
  #   condition = (
  #     self.use_instance_requirements == false ?
  #     length(self.instance_types) > 0 ||
  #     (self.cpu_workers.on_demand_count + self.cpu_workers.spot_count +
  #     self.gpu_workers.on_demand_count + self.gpu_workers.spot_count) == 0 :
  #     true
  #   )
  #   error_message = "When use_instance_requirements is false, must specify at least one instance_type if creating workers."
  # }
}

#===============================================================================
# IAM Configuration
#===============================================================================

variable "iam_config" {
  description = "IAM configuration settings"
  type = object({
    control_plane_role_name = optional(string, "control-plane-role-name")
    worker_role_name        = optional(string, "cpu-worker-role-name")
    gpu_worker_role_name    = optional(string, "gpu-worker-role-name") # Optional separate GPU role with additional permissions
  })
  default = {}
}

#===============================================================================
# NAT Configuration
#===============================================================================

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

#===============================================================================
# Control Plane Configuration
#===============================================================================

variable "k8s_control_plane_config" {
  description = "Kubernetes control plane configuration"
  type = object({
    instance_count      = optional(number, 1)
    instance_type       = optional(string, "t4g.medium")
    on_demand_count     = optional(number, 1) # Control plane typically on-demand
    spot_count          = optional(number, 0) # Control plane rarely uses spot
    spot_instance_types = optional(list(string), [])

    # Control plane can override instance_config defaults if needed
    block_device_mappings = optional(list(object({
      device_name           = string
      volume_size           = number
      volume_type           = optional(string, "gp3")
      delete_on_termination = optional(bool, true)
      encrypted             = optional(bool, true)
      iops                  = optional(number, null)
      throughput            = optional(number, null)
      kms_key_id            = optional(string, null)
    })), null) # null = use instance_config defaults
  })
  default = {}
}

#===============================================================================
# Cost Optimization
#===============================================================================

variable "cost_optimization" {
  description = "Cost optimization settings"
  type = object({
    enable_spot_instances = optional(bool, true)
    enable_vpc_endpoints  = optional(bool, true)
  })
  default = {}
}

#===============================================================================
# Legacy Configuration (for backward compatibility)
#===============================================================================

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

#===============================================================================
# Additional Kubernetes Configuration (for backward compatibility)
#===============================================================================

variable "k8s_config" {
  description = "Additional Kubernetes settings (legacy compatibility)"
  type = object({
    ssh_private_key_path   = optional(string, "~/.ssh/lw.pem")
    ssh_public_key_path    = optional(string, "~/.ssh/lw.pem.pub")
    k8s_user               = optional(string, "ubuntu")
    k8s_major_minor_stream = optional(string, "1.33.3")
    k8s_full_patch_version = optional(string, "1.33.0")
    k8s_apt_package_suffix = optional(string, "-00")
  })
  default = {}
}
