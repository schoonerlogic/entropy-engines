# NATS Messaging Module Variables

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
}

variable "cloud_provider" {
  description = "Cloud provider (aws, gcp, azure)"
  type        = string
}

variable "cloud_config" {
  description = "Cloud-specific configuration"
  type = object({
    region             = string
    availability_zones = list(string)
    instance_profile   = string
    security_group_ids = list(string)
    subnet_ids         = list(string)
    vpc_id             = string
  })
}

variable "nats_cluster_size" {
  description = "Number of NATS server instances"
  type        = number
  default     = 3
}

variable "nats_instance_type" {
  description = "Instance type for NATS servers"
  type        = string
  default     = "t3.small"
}

variable "nats_version" {
  description = "NATS server version"
  type        = string
  default     = "2.10.0"
}