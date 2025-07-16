variable "vpc_id" {
  description = "VPC ID where the cluster is deployed"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for interface endpoints"
  type        = list(string)
}

variable "route_table_ids" {
  description = "Route table IDs for gateway endpoints"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for interface endpoints"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
}

variable "models" {
  description = "List of Hugging Face models to download"
  type = list(object({
    model_id    = string
    destination = string
  }))
  default = [
    {
      model_id    = "distilbert-base-uncased",
      destination = "nlp/distilbert"
    },
    {
      model_id    = "microsoft/resnet-50",
      destination = "vision/resnet"
    }
  ]
}
