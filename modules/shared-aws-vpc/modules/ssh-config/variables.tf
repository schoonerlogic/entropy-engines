# modules/ssh-config/variables.tf
variable "project" {}
variable "bastion_host" {}
variable "bastion_user" {}
variable "ssh_private_key_path" {}

variable "output_path" {
  description = "Local path to write the SSH config file"
  type        = string
}

variable "template_path" {
  description = "Path to the ssh_config.tpl template"
  type        = string
}


