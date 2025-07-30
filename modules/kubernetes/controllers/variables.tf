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

variable "base_aws_ami" {
  description = "AMI ID for controller instances"
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

variable "pod_cidr_block" {
  description = "CIDR block for Kubernetes pods"
  type        = string
}

variable "service_cidr_block" {
  description = "CIDR block for Kubernetes services"
  type        = string
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
}

#===============================================================================
# SSH Configuration
#===============================================================================

variable "ssh_key_name" {
  description = "Name of the SSH key pair"
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
