variable "aws_region" {}
variable "project" {}

variable "instance_count" {}
variable "subnet_ids" {}
variable "instance_type" {}
variable "ssh_key_name" {}
variable "ssh_private_key_path" {}

variable "ssh_public_key_path" {
  description = "Path to ssh key"
  type        = string
}

variable "cluster_name" {}
variable "security_group_ids" {
  type = list(string)
}
variable "associate_public_ip_address" {
  type    = string
  default = "false"
}
variable "bastion_host" {}
variable "bastion_user" {}
variable "instance_interruption_behavior" {
  default = "terminate"
}
variable "k8s_user" {}

variable "enable_provisioner" {
  default = false
}

variable "pod_cidr_block" {
  type = string
}

variable "service_cidr_block" {
  type = string
}

variable "enable_k8s_api_nlb" {
  description = "Set to true to provision a Network Load Balancer for the Kubernetes API server. If false, the first controller's IP will be used."
  type        = bool
  default     = false # Default to false for a leaner dev setup, or true if you use it more often
}

variable "k8s_major_minor_stream" {
  description = "The Kubernetes major.minor version for APT repository setup (e.g., '1.33'). This is used to construct the repository URL."
  type        = string
  # Example: default = "1.33"
}

variable "k8s_full_patch_version" {
  description = "The full Kubernetes patch version to target for installation and for kubeadm's ClusterConfiguration (e.g., '1.33.1')."
  type        = string
  # Example: default = "1.33.1"
}

variable "k8s_apt_package_suffix" {
  description = "The suffix needed for apt to install a specific k8s package version (e.g., '-00' or found via 'apt-cache madison kubeadm'). Often combines with k8s_full_patch_version."
  type        = string
}

variable "spot_instance_types" {
  description = "List of acceptable EC2 instances for spot fleet"
  type        = list(string)
  default     = ["g5g.xlarge", "g5g.2xlarge"]
}

variable "base_ami_id" {
  description = "ID of prebaked AMI for worker-gpus"
  type        = string
}


variable "controller_role_name" {
  description = "Name of the IAM role for controller instances"
  type        = string
}

variable "iam_policy_version" {
  description = "Version tracking for policy applied to template"
  type        = string
}

variable "controller_on_demand_count" {
  description = "The number of On-Demand controller instances to run."
  type        = number
  default     = 1
}

variable "controller_spot_count" {
  description = "The number of Spot controller instances to run."
  type        = number
  default     = 2
}


