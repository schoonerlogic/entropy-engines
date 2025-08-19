# modules/controllers/variables.tf
# Individual variables for Kubernetes control plane

#===============================================================================
# Core Configuration
#===============================================================================

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod, etc.)"
  type        = string
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
# Instance Configuration
#===============================================================================

variable "on_demand_count" {
  description = "Number of on-demand controller instances"
  type        = number
  default     = 1
}

variable "spot_count" {
  description = "Number of spot controller instances"
  type        = number
  default     = 0
}

variable "instance_types" {
  description = "List of instance types for controllers"
  type        = list(string)
}

variable "aws_ami" {
  description = "AMI ID for controller instances"
  type        = string
  default     = ""
}

#===============================================================================
# Kubernetes Configuration
#===============================================================================

variable "k8s_user" {
  description = "Kubernetes user for the cluster"
  type        = string
}

variable "k8s_major_minor_stream" {
  description = "Kubernetes version (major.minor) for apt repository"
  type        = string
}

variable "k8s_full_patch_version" {
  description = "Full Kubernetes patch version"
  type        = string
}

variable "k8s_apt_package_suffix" {
  description = "APT package suffix for Kubernetes"
  type        = string
}

variable "k8s_package_version_string" {
  description = "Full Kubernetes package version string for apt (e.g., 1.33.1-00 or 1.33.1-1.1)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+-[0-9]+(\\.[0-9]+)?$", var.k8s_package_version_string))
    error_message = "Package version must be in format 'major.minor.patch-suffix' or 'major.minor.patch-suffix.suffix2' (e.g., 1.33.1-00 or 1.33.1-1.1)."
  }
}

variable "pod_cidr_block" {
  description = "CIDR block for Kubernetes pods"
  type        = string
  default     = ""
}

variable "service_cidr_block" {
  description = "CIDR block for Kubernetes services"
  type        = string
  default     = ""
}

#===============================================================================
# Networking
#===============================================================================

variable "subnet_ids" {
  description = "List of subnet IDs for controller instances"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for controllers"
  type        = list(string)
}

#===============================================================================
# IAM
#===============================================================================

variable "control_plane_role_name" {
  description = "Name of the IAM role for control plane instances"
  type        = string
}


#===============================================================================
# S3 Bootstrap Configuration
#===============================================================================

variable "k8s_scripts_bucket_name" {
  description = "Name of the S3 bucket containing bootstrap scripts"
  type        = string
  default     = ""
}

variable "script_dependencies" {
  description = "Script objects to trigger launch template replacement"
  type        = any
  default     = {}
}
#===============================================================================
# SSH Configuration
#===============================================================================
variable "ssh_key_name" {
  description = "Name of SSH public key"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key file"
  type        = string
}

variable "ssm_join_command_path" {
  description = "SSM Parameter Store path for the Kubernetes join command"
  type        = string
}

variable "ssm_certificate_key_path" {
  description = "Certificate for securing parameter join key"
  type        = string
}
#===============================================================================
# Block Device Mappings
#===============================================================================

variable "block_device_mappings" {
  description = "Block device mappings for controller instances"
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
  default = [
    {
      device_name           = "/dev/sda1"
      volume_size           = 50
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  ]
}

#===============================================================================
# Auto Scaling Group Configuration
#===============================================================================

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

variable "capacity_timeout" {
  description = "Timeout for capacity changes"
  type        = string
  default     = "15m"
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
# Tags
#===============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
