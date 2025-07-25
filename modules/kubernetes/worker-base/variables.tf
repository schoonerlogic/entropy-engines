# modules/worker-base/variables.tf
# Clean, individual variables - exactly what the base module needs

#===============================================================================
# Core Configuration
#===============================================================================

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
}

variable "worker_type" {
  description = "Type of worker (cpu or gpu)"
  type        = string
  validation {
    condition     = contains(["cpu", "gpu"], var.worker_type)
    error_message = "Worker type must be either 'cpu' or 'gpu'."
  }
}

#===============================================================================
# Instance Configuration
#===============================================================================

variable "instance_types" {
  description = "List of instance types to use"
  type        = list(string)
}

variable "use_instance_requirements" {
  description = "Whether to use instance requirements instead of specific instance types"
  type        = bool
  default     = false
}

variable "instance_requirements" {
  description = "Instance requirements for mixed instances policy"
  type = object({
    vcpu_count = object({
      min = number
      max = number
    })
    memory_mib = object({
      min = number
      max = number
    })
    cpu_architectures             = optional(list(string))
    excluded_instance_generations = optional(list(string))
    excluded_instance_types       = optional(list(string))
    allowed_instance_types        = optional(list(string))
    instance_categories           = optional(list(string))
    burstable_performance         = optional(string)
    bare_metal                    = optional(string)
    require_hibernate_support     = optional(bool)

    # Storage requirements
    local_storage       = optional(string)
    local_storage_types = optional(list(string))
    total_local_storage_gb = optional(object({
      min = optional(number)
      max = optional(number)
    }))

    # Network performance
    network_interface_count = optional(object({
      min = optional(number)
      max = optional(number)
    }))
    network_bandwidth_gbps = optional(object({
      min = optional(number)
      max = optional(number)
    }))

    # EBS bandwidth
    baseline_ebs_bandwidth_mbps = optional(object({
      min = optional(number)
      max = optional(number)
    }))

    # GPU-specific (for GPU workers)
    accelerator_count = optional(object({
      min = optional(number)
      max = optional(number)
    }))
    accelerator_manufacturers = optional(list(string))
    accelerator_names         = optional(list(string))
    accelerator_types         = optional(list(string))
  })
  default = null
}

variable "on_demand_count" {
  description = "Number of on-demand instances"
  type        = number
}

variable "spot_count" {
  description = "Number of spot instances"
  type        = number
}

variable "base_ami" {
  description = "AMI ID for worker instances"
  type        = string
}

#===============================================================================
# Kubernetes Configuration
#===============================================================================

variable "k8s_user" {
  description = "Kubernetes user for the cluster"
  type        = string
}

variable "k8s_major_minor_stream" {
  description = "Kubernetes version (major.minor)"
  type        = string
}

variable "cluster_dns_ip" {
  description = "Cluster DNS IP address"
  type        = string
}

#===============================================================================
# Networking
#===============================================================================

variable "subnet_ids" {
  description = "List of subnet IDs for worker instances"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs"
  type        = list(string)
}

variable "ssh_key_name" {
  description = "Name of the SSH key pair"
  type        = string
}

#===============================================================================
# IAM
#===============================================================================

variable "worker_role_name" {
  description = "Name of the IAM role for worker instances"
  type        = string
}

variable "iam_policy_version" {
  description = "Version of the IAM policy"
  type        = string
}

#===============================================================================
# S3 Bootstrap Configuration
#===============================================================================

variable "bootstrap_bucket_name" {
  description = "Name of the S3 bucket containing bootstrap scripts"
  type        = string
}

variable "bootstrap_script_name" {
  description = "Name of the bootstrap script to upload to S3"
  type        = string
  default     = null # Will be determined by worker_type if not specified
}

variable "bootstrap_bucket_dependency" {
  description = "S3 bucket dependency"
  type        = any
  default     = null
}

#===============================================================================
# Auto Scaling Group Configuration
#===============================================================================

variable "min_size" {
  description = "Minimum size of ASG (defaults to total instance count)"
  type        = number
  default     = null
}

variable "max_size" {
  description = "Maximum size of ASG (defaults to total instance count)"
  type        = number
  default     = null
}

variable "health_check_type" {
  description = "Type of health check (EC2 or ELB)"
  type        = string
  default     = "EC2"
}

variable "health_check_grace_period" {
  description = "Health check grace period in seconds"
  type        = number
  default     = 300
}

variable "min_healthy_percentage" {
  description = "Minimum healthy percentage during instance refresh"
  type        = number
  default     = 50
}

variable "instance_warmup" {
  description = "Instance warmup time in seconds"
  type        = number
  default     = 300
}

variable "capacity_timeout" {
  description = "Timeout for capacity changes"
  type        = string
  default     = "15m"
}

variable "instance_refresh_triggers" {
  description = "List of triggers for instance refresh"
  type        = list(string)
  default     = ["tag"]
}

#===============================================================================
# Spot Configuration
#===============================================================================

variable "spot_allocation_strategy" {
  description = "Spot allocation strategy"
  type        = string
  default     = "capacity-optimized"
}

variable "spot_instance_pools" {
  description = "Number of spot instance pools"
  type        = number
  default     = 2
}

#===============================================================================
# Storage Configuration
#===============================================================================

variable "block_device_mappings" {
  description = "Block device mappings for instances"
  type = list(object({
    device_name           = string
    volume_size           = number
    volume_type           = optional(string, "gp3")
    delete_on_termination = optional(bool, true)
    encrypted             = optional(bool, true)
    iops                  = optional(number, null)
    throughput            = optional(number, null)
    kms_key_id            = optional(string, null)
  }))
}

#===============================================================================
# GPU-Specific Configuration (only used by GPU workers)
#===============================================================================

variable "gpu_type" {
  description = "Type of GPU (nvidia, amd, etc.)"
  type        = string
  default     = null
}

variable "gpu_memory_min" {
  description = "Minimum GPU memory in GiB"
  type        = number
  default     = null
}

#===============================================================================
# Tags
#===============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
