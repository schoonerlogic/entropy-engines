
variable "aws_config" {
  description = "Core infrastructure configuration settings"
  type = object({
    environment                    = optional(string, "dev")
    ssh_key_name                   = string
    subnet_ids                     = string
    security_group_ids             = string
    associate_public_ip_address    = string
    bastion_host                   = string
    bastion_user                   = string
    instance_interruption_behavior = string
    enable_provisioner             = string
    pod_cidr_block                 = string
    service_cidr_block             = string
    controller_role_name           = string
    iam_policy_version             = string
    base_ami_id                    = string
    iam_instance_profile_name      = string
  })
}

variable "k8s_config" {
  description = "Kubernetes settings"
  type = object({
    cluster_name           = optional(string, "engines")
    instance_type          = optional(string, "t4g.medium")
    on_demand_count        = optional(number, 0)
    spot_count             = optional(number, 0)
    ssh_public_key_path    = optional(string, "~/.ssh/lw.pem.pub")
    k8s_user               = optional(string, "ubuntu")
    k8s_major_minor_stream = optional(string, "1.33.3")
    k8s_full_patch_version = optional(string, "1.33.0")
    k8s_apt_package_suffix = optional(string, "-00")
    spot_instance_types    = optional(string, "m7g.medium")
    cluster_dns_ip         = optional(string, "_")
    use_base_ami           = optional(bool, false)
  })
}





