# modules/cpu-workers/variables.tf
variable "instance_count" {}

variable "cluster_dns_ip" {
  description = "Setup in module network"
  type        = string
}
variable "instance_type" {}
variable "spot_instance_types" {
  description = "List of acceptable EC2 instances for spot fleet"
  type        = list(string)
  default     = ["r6g.2xlarge", "r6gd.2xlarge", "i4g.2xlarge", "c7gd.2xlarge", "g5g.2xlarge", "i4g.xlarge"]
}

variable "spot_instance_type_weights" {
  description = "Map of instance types to their weighted capacity (e.g., based on vCPU). Used if target_capacity_unit_type is set."
  type        = map(string) # e.g., {"m5.large" = "2", "m5.xlarge" = "4"}
  default     = {}
}

variable "target_capacity_unit_type" {
  description = "The unit for target_capacity. Use 'instances' or 'vcpu'. If 'vcpu', provide spot_instance_type_weights."
  type        = string
  default     = "instances" # Default to counting instances
  validation {
    condition     = contains(["instances", "vcpu"], var.target_capacity_unit_type)
    error_message = "Allowed values for target_capacity_unit_type are 'instances' or 'vcpu'."
  }
}

variable "base_ami_id" {
  description = "ID of prebaked AMI for worker-cpus"
  type        = string
}

variable "use_base_ami" {
  description = "Set to true when not building with user_data and using prebuilt ami"
  type        = bool
}

variable "k8s_major_minor_stream" {
  description = "The Kubernetes major.minor version for APT repository setup (e.g., '1.33'). This is used to construct the repository URL."
  type        = string
  # Example: default = "1.33"
}


variable "ssm_join_command_path" {}

variable "subnet_ids" {}
variable "ssh_key_name" {}
variable "ssh_private_key_path" {}
variable "ssh_public_key_path" {}
variable "cluster_name" {}
variable "k8s_user" {}
variable "security_group_ids" {
  type = list(string)
}
variable "iam_instance_profile_name" {}
variable "spot_fleet_iam_role_arn" {}

variable "associate_public_ip_address" {}
variable "bastion_host" {}
variable "bastion_user" {}


variable "spot_type" {
  default = "one-time"
}

variable "instance_interruption_behavior" {
  default = "terminate"
}

variable "worker_s3_bootstrap_bucket" {}
variable "worker_cpu_bootstrap_script" {}

variable "iam_policy_version" {
  description = "Version tracking for policy applied to template"
  type        = string
}

variable "cpu_on_demand_count" {
  description = "The number of On-Demand cpu worker instances to run."
  type        = number
  default     = 1
}

variable "cpu_spot_count" {
  description = "The number of Spot cpu worker instances to run."
  type        = number
  default     = 2
}
