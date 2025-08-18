# modules/kubernetes/gpu-workers/variables.tf
# Variables for GPU worker module

#===============================================================================
# Cluster Configuration
#===============================================================================

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.cluster_name))
    error_message = "Cluster name must contain only alphanumeric characters and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "log_level" {
  description = "Logging verbosity: ERROR, WARN, INFO, DEBUG, TRACE"
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["ERROR", "WARN", "INFO", "DEBUG", "TRACE"], var.log_level)
    error_message = "Invalid log level. Must be ERROR, WARN, INFO, DEBUG, or TRACE."
  }
}


#===============================================================================
# Kubernetes Configuration
#===============================================================================

variable "k8s_user" {
  description = "Username for Kubernetes operations"
  type        = string
  default     = "k8s-admin"
}

variable "k8s_major_minor_stream" {
  description = "Kubernetes major.minor version stream (e.g., 1.33)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.k8s_major_minor_stream))
    error_message = "Kubernetes version stream must be in format 'major.minor' (e.g., 1.33)."
  }
}

variable "k8s_package_version_string" {
  description = "Full Kubernetes package version string for apt (e.g., 1.33.1-00 or 1.33.1-1.1)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+-[0-9]+(\\.[0-9]+)?$", var.k8s_package_version_string))
    error_message = "Package version must be in format 'major.minor.patch-suffix' or 'major.minor.patch-suffix.suffix2' (e.g., 1.33.1-00 or 1.33.1-1.1)."
  }
}

variable "ssm_join_command_path" {
  description = "SSM Parameter Store path for the Kubernetes join command"
  type        = string
}

#===============================================================================
# S3 Configuration
#===============================================================================

variable "k8s_scripts_bucket_name" {
  description = "Name of the S3 bucket containing Kubernetes setup scripts"
  type        = string
  default     = ""
}

#===============================================================================
# GPU Worker Instance Configuration
#===============================================================================

variable "gpu_instance_types" {
  description = "List of EC2 instance types for GnU workers"
  type        = list(string)
  default     = ["m6i.large", "m6i.xlarge", "m5.large", "m5.xlarge"]

  validation {
    condition     = length(var.gpu_instance_types) > 0
    error_message = "At least one GPU instance type must be specified."
  }
}

variable "gpu_on_demand_count" {
  description = "Number of on-demand GPU worker instances"
  type        = number
  default     = 1

  validation {
    condition     = var.gpu_on_demand_count >= 0
    error_message = "On-demand count must be non-negative."
  }
}

variable "gpu_spot_count" {
  description = "Number of spot GPU worker instances"
  type        = number
  default     = 0

  validation {
    condition     = var.gpu_spot_count >= 0
    error_message = "Spot count must be non-negative."
  }
}

#===============================================================================
# Instance Requirements (Alternative to instance_types)
#===============================================================================

variable "use_instance_requirements" {
  description = "Whether to use instance requirements instead of specific instance types"
  type        = bool
  default     = false
}

variable "instance_requirements" {
  description = "Instance requirements for GPU workers (used when use_instance_requirements is true)"
  type = object({
    vcpu_count = object({
      min = number
      max = number
    })
    memory_mib = object({
      min = number
      max = number
    })
    gpu_architectures     = optional(list(string))
    instance_categories   = optional(list(string))
    burstable_performance = optional(string)
  })
  default = null
}

variable "gpu_type" {
  description = "GPU processor type"
  type        = string
  default     = "nvidia"
}



#===============================================================================
# Infrastructure Configuration
#===============================================================================

variable "aws_ami" {
  description = "AMI ID for GPU worker instances"
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^ami-[0-9a-f]{8,}$", var.aws_ami))
    error_message = "AMI ID must be in the format ami-xxxxxxxx."
  }
}

variable "subnet_ids" {
  description = "List of subnet IDs where GPU workers will be launched"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "At least one subnet ID must be provided."
  }
}

variable "security_group_ids" {
  description = "List of security group IDs for GPU workers"
  type        = list(string)

  validation {
    condition     = length(var.security_group_ids) > 0
    error_message = "At least one security group ID must be provided."
  }
}

variable "worker_role_name" {
  description = "Name of the IAM role for GPU worker instances"
  type        = string
}

#===============================================================================
# Auto Scaling Group Configuration
#===============================================================================

variable "min_size" {
  description = "Minimum size of the GPU worker Auto Scaling Group"
  type        = number
  default     = null
}

variable "max_size" {
  description = "Maximum size of the GPU worker Auto Scaling Group"
  type        = number
  default     = null
}

variable "health_check_type" {
  description = "Type of health check for the Auto Scaling Group"
  type        = string
  default     = "EC2"

  validation {
    condition     = contains(["EC2", "ELB"], var.health_check_type)
    error_message = "Health check type must be either 'EC2' or 'ELB'."
  }
}

variable "health_check_grace_period" {
  description = "Health check grace period in seconds"
  type        = number
  default     = 300

  validation {
    condition     = var.health_check_grace_period >= 0
    error_message = "Health check grace period must be non-negative."
  }
}

variable "capacity_timeout" {
  description = "Maximum time to wait for the desired capacity to be reached"
  type        = string
  default     = "10m"
}

#===============================================================================
# Spot Instance Configuration
#===============================================================================

variable "spot_allocation_strategy" {
  description = "Strategy for allocating spot instances"
  type        = string
  default     = "diversified"

  validation {
    condition     = contains(["lowest-price", "diversified", "capacity-optimized"], var.spot_allocation_strategy)
    error_message = "Spot allocation strategy must be one of: lowest-price, diversified, capacity-optimized."
  }
}

#===============================================================================
# Instance Refresh Configuration
#===============================================================================

variable "min_healthy_percentage" {
  description = "Minimum percentage of healthy instances during instance refresh"
  type        = number
  default     = 50

  validation {
    condition     = var.min_healthy_percentage >= 0 && var.min_healthy_percentage <= 100
    error_message = "Min healthy percentage must be between 0 and 100."
  }
}

variable "instance_warmup" {
  description = "Instance warmup time in seconds during instance refresh"
  type        = number
  default     = 300

  validation {
    condition     = var.instance_warmup >= 0
    error_message = "Instance warmup must be non-negative."
  }
}

#===============================================================================
# Storage Configuration
#===============================================================================

variable "block_device_mappings" {
  description = "Block device mappings for GPU worker instances"
  type = list(object({
    device_name           = string
    volume_size           = number
    volume_type           = string
    delete_on_termination = bool
    encrypted             = bool
    iops                  = optional(number)
    throughput            = optional(number)
    kms_key_id            = optional(string)
  }))
  default = [
    {
      device_name           = "/dev/sda1"
      volume_size           = 50
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
      iops                  = 3000
      throughput            = 125
    }
  ]
}

#===============================================================================
# Tagging Configuration
#===============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to GPU worker resources"
  type        = map(string)
  default     = {}
}

variable "iam_policy_version" {
  description = "Version of the IAM policy (for tracking updates)"
  type        = string
  default     = "1.0"
}

#===============================================================================
# Monitoring and Logging Configuration
#===============================================================================

variable "enable_cloudwatch_logs" {
  description = "Whether to enable CloudWatch logging for GPU workers"
  type        = bool
  default     = false
}

variable "enable_notifications" {
  description = "Whether to enable SNS notifications for GPU worker events"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

#===============================================================================
# Advanced Configuration
#===============================================================================

variable "enable_detailed_monitoring" {
  description = "Whether to enable detailed CloudWatch monitoring for instances"
  type        = bool
  default     = true
}

variable "enable_instance_metadata_tags" {
  description = "Whether to enable instance metadata tags"
  type        = bool
  default     = true
}

variable "metadata_hop_limit" {
  description = "The desired HTTP PUT response hop limit for instance metadata requests"
  type        = number
  default     = 2

  validation {
    condition     = var.metadata_hop_limit >= 1 && var.metadata_hop_limit <= 64
    error_message = "Metadata hop limit must be between 1 and 64."
  }
}
