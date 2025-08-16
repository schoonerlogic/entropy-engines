#===============================================================================
# Required Variables
#===============================================================================

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
}

variable "worker_type" {
  description = "Type of worker (e.g., 'cpu', 'gpu')"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., 'dev', 'staging', 'prod')"
  type        = string
}

variable "aws_ami" {
  description = "Base AMI ID to use for worker instances"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs where worker instances will be launched"
  type        = list(string)
}
variable "security_group_ids" {
  description = "List of security group IDs to attach to worker instances"
  type        = list(string)
}

variable "worker_role_name" {
  description = "Name of the IAM role for worker instances"
  type        = string
}

variable "k8s_scripts_bucket_name" {
  description = "Name of the S3 bucket containing Kubernetes setup scripts"
  type        = string
}

#===============================================================================
# Instance Configuration
#===============================================================================

variable "on_demand_count" {
  description = "Number of on-demand instances to launch"
  type        = number
  default     = 0
}

variable "spot_count" {
  description = "Number of spot instances to launch"
  type        = number
  default     = 0
}

variable "instance_types" {
  description = "List of EC2 instance types to use for workers"
  type        = list(string)
  default     = ["t3.medium"]
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
    cpu_architectures     = optional(list(string))
    instance_categories   = optional(list(string))
    burstable_performance = optional(string)
  })
  default = null
}

#===============================================================================
# Auto Scaling Group Configuration
#===============================================================================

variable "min_size" {
  description = "Minimum size of the Auto Scaling Group (defaults to total instance count if not provided)"
  type        = number
  default     = null
}

variable "max_size" {
  description = "Maximum size of the Auto Scaling Group (defaults to total instance count if not provided)"
  type        = number
  default     = null
}

variable "health_check_type" {
  description = "Health check type for the Auto Scaling Group"
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
}

variable "capacity_timeout" {
  description = "Maximum duration that Terraform should wait for ASG instances to be healthy before timing out"
  type        = string
  default     = "10m"
}

variable "spot_allocation_strategy" {
  description = "Strategy to use when launching Spot instances"
  type        = string
  default     = "diversified"

  validation {
    condition     = contains(["lowest-price", "diversified", "capacity-optimized"], var.spot_allocation_strategy)
    error_message = "Spot allocation strategy must be one of: lowest-price, diversified, capacity-optimized."
  }
}

variable "min_healthy_percentage" {
  description = "Minimum healthy percentage during instance refresh"
  type        = number
  default     = 90

  validation {
    condition     = var.min_healthy_percentage >= 0 && var.min_healthy_percentage <= 100
    error_message = "Minimum healthy percentage must be between 0 and 100."
  }
}

variable "instance_warmup" {
  description = "Instance warmup time in seconds during instance refresh"
  type        = number
  default     = 300
}

variable "script_dependencies" {
  description = "Script objects to trigger launch template replacement"
  type        = any
  default     = {}
}

#===============================================================================
# Storage Configuration
#===============================================================================

variable "block_device_mappings" {
  description = "Block device mappings for worker instances"
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
      device_name           = "/dev/xvda"
      volume_size           = 20
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  ]
}

#===============================================================================
# Optional Configuration
#===============================================================================

variable "ssh_key_name" {
  description = "Name of the AWS key pair to use for instance access"
  type        = string
  default     = null
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "iam_policy_version" {
  description = "Version of the IAM policy being used"
  type        = string
  default     = "1.0"
}

#===============================================================================
# GPU-Specific Variables (null for CPU workers)
#===============================================================================

variable "gpu_type" {
  description = "Type of GPU for GPU workers (null for CPU workers)"
  type        = string
  default     = null
}

variable "gpu_memory_min" {
  description = "Minimum GPU memory in GB for GPU workers (null for CPU workers)"
  type        = number
  default     = null
}
