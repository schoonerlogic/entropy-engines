# modules/ssh-config/variables.tf
variable "cluster_name" {}

variable "bastion_host" {
  description = "Public ip of bastion instance"
  type        = string
}

variable "bastion_user" {}
variable "k8s_user" {}
variable "ssh_private_key_path" {}

variable "output_path" {
  description = "Local path to write the SSH config file"
  type        = string
  default     = ""
}

variable "template_path" {
  description = "Path to the ssh_config.tpl template"
  type        = string
  default     = ""
}

variable "controller_private_ips" {
  type    = list(string)
  default = []
}
variable "worker_gpu_private_ips" {
  type    = list(string)
  default = []
}

variable "worker_cpu_private_ips" {
  type    = list(string)
  default = []
}

variable "nats_private_ips" {
  type    = list(string)
  default = []
}

# variable "tooling_node_private_ips" {
#   type    = list(string)
#   default = []
# }



