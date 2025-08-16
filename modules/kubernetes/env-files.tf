# resource "local_file" "00-shared-functions_env" {
#   content  = <<-EOT
# CLUSTER_NAME=${local.cluster_name}
# K8S_USER=${local.k8s_user}
# K8S_VERSION=${local.k8s_version}
# SERVICE_CIDR=${local.service_cidr}
# POD_CIDR=${local.pod_cidr}
# NODE_NAME=${local.node_name}
# NODE_ROLE=${local.node_role}
# AWS_REGION=${local.aws_region}
# LOG_LEVEL=${local.log_level}
# EOT
#   filename = "${path.module}/generated/env/00-shared-functions.env"
# }
#
# resource "aws_s3_object" "00-shared-functions_env_s3" {
#   bucket = var.k8s_scripts_bucket_name
#   key    = "scripts/controllers/env/00-shared-functions.env"
#   source = "${path.module}/generated/env/00-shared-functions.env"
#   etag   = filemd5("${path.module}/generated/env/00-shared-functions.env")
# }
#
# resource "local_file" "01-install-user-and-tooling_env" {
#   content  = <<-EOT
# CLUSTER_NAME=${local.cluster_name}
# K8S_USER=${local.k8s_user}
# K8S_VERSION=${local.k8s_version}
# SERVICE_CIDR=${local.service_cidr}
# POD_CIDR=${local.pod_cidr}
# NODE_NAME=${local.node_name}
# NODE_ROLE=${local.node_role}
# AWS_REGION=${local.aws_region}
# LOG_LEVEL=${local.log_level}
# EOT
#   filename = "${path.module}/generated/env/01-install-user-and-tooling.env"
# }
#
# resource "aws_s3_object" "01-install-user-and-tooling_env_s3" {
#   bucket = var.k8s_scripts_bucket_name
#   key    = "scripts/controllers/env/01-install-user-and-tooling.env"
#   source = "${path.module}/generated/env/01-install-user-and-tooling.env"
#   etag   = filemd5("${path.module}/generated/env/01-install-user-and-tooling.env")
# }
#
# resource "local_file" "02-install-kubernetes_env" {
#   content  = <<-EOT
# CLUSTER_NAME=${local.cluster_name}
# K8S_USER=${local.k8s_user}
# K8S_VERSION=${local.k8s_version}
# SERVICE_CIDR=${local.service_cidr}
# POD_CIDR=${local.pod_cidr}
# NODE_NAME=${local.node_name}
# NODE_ROLE=${local.node_role}
# AWS_REGION=${local.aws_region}
# LOG_LEVEL=${local.log_level}
# EOT
#   filename = "${path.module}/generated/env/02-install-kubernetes.env"
# }
#
# resource "aws_s3_object" "02-install-kubernetes_env_s3" {
#   bucket = var.k8s_scripts_bucket_name
#   key    = "scripts/controllers/env/02-install-kubernetes.env"
#   source = "${path.module}/generated/env/02-install-kubernetes.env"
#   etag   = filemd5("${path.module}/generated/env/02-install-kubernetes.env")
# }
#
# resource "local_file" "03-join-cluster_env" {
#   content  = <<-EOT
# CLUSTER_NAME=${local.cluster_name}
# K8S_USER=${local.k8s_user}
# K8S_VERSION=${local.k8s_version}
# SERVICE_CIDR=${local.service_cidr}
# POD_CIDR=${local.pod_cidr}
# NODE_NAME=${local.node_name}
# NODE_ROLE=${local.node_role}
# AWS_REGION=${local.aws_region}
# LOG_LEVEL=${local.log_level}
# EOT
#   filename = "${path.module}/generated/env/03-join-cluster.env"
# }
#
# resource "aws_s3_object" "03-join-cluster_env_s3" {
#   bucket = var.k8s_scripts_bucket_name
#   key    = "scripts/controllers/env/03-join-cluster.env"
#   source = "${path.module}/generated/env/03-join-cluster.env"
#   etag   = filemd5("${path.module}/generated/env/03-join-cluster.env")
# }
#
# resource "local_file" "04-install-cni_env" {
#   content  = <<-EOT
# CLUSTER_NAME=${local.cluster_name}
# K8S_USER=${local.k8s_user}
# K8S_VERSION=${local.k8s_version}
# SERVICE_CIDR=${local.service_cidr}
# POD_CIDR=${local.pod_cidr}
# NODE_NAME=${local.node_name}
# NODE_ROLE=${local.node_role}
# AWS_REGION=${local.aws_region}
# LOG_LEVEL=${local.log_level}
# EOT
#   filename = "${path.module}/generated/env/04-install-cni.env"
# }
#
# resource "aws_s3_object" "04-install-cni_env_s3" {
#   bucket = var.k8s_scripts_bucket_name
#   key    = "scripts/controllers/env/04-install-cni.env"
#   source = "${path.module}/generated/env/04-install-cni.env"
#   etag   = filemd5("${path.module}/generated/env/04-install-cni.env")
# }
#
# resource "local_file" "05-install-addons_env" {
#   content  = <<-EOT
# CLUSTER_NAME=${local.cluster_name}
# K8S_USER=${local.k8s_user}
# K8S_VERSION=${local.k8s_version}
# SERVICE_CIDR=${local.service_cidr}
# POD_CIDR=${local.pod_cidr}
# NODE_NAME=${local.node_name}
# NODE_ROLE=${local.node_role}
# AWS_REGION=${local.aws_region}
# LOG_LEVEL=${local.log_level}
# EOT
#   filename = "${path.module}/generated/env/05-install-addons.env"
# }
#
# resource "aws_s3_object" "05-install-addons_env_s3" {
#   bucket = var.k8s_scripts_bucket_name
#   key    = "scripts/controllers/env/05-install-addons.env"
#   source = "${path.module}/generated/env/05-install-addons.env"
#   etag   = filemd5("${path.module}/generated/env/05-install-addons.env")
# }
#
# resource "local_file" "k8s-setup-main_env" {
#   content  = <<-EOT
# CLUSTER_NAME=${local.cluster_name}
# K8S_USER=${local.k8s_user}
# K8S_VERSION=${local.k8s_version}
# SERVICE_CIDR=${local.service_cidr}
# POD_CIDR=${local.pod_cidr}
# NODE_NAME=${local.node_name}
# NODE_ROLE=${local.node_role}
# AWS_REGION=${local.aws_region}
# LOG_LEVEL=${local.log_level}
# EOT
#   filename = "${path.module}/generated/env/k8s-setup-main.env"
# }
#
# resource "aws_s3_object" "k8s-setup-main_env_s3" {
#   bucket = var.k8s_scripts_bucket_name
#   key    = "scripts/controllers/env/k8s-setup-main.env"
#   source = "${path.module}/generated/env/k8s-setup-main.env"
#   etag   = filemd5("${path.module}/generated/env/k8s-setup-main.env")
# }
#
# resource "local_file" "k8s-setup-workers_env" {
#   content  = <<-EOT
# CLUSTER_NAME=${local.cluster_name}
# K8S_USER=${local.k8s_user}
# K8S_VERSION=${local.k8s_version}
# SERVICE_CIDR=${local.service_cidr}
# POD_CIDR=${local.pod_cidr}
# NODE_NAME=${local.node_name}
# NODE_ROLE=${local.node_role}
# AWS_REGION=${local.aws_region}
# LOG_LEVEL=${local.log_level}
# EOT
#   filename = "${path.module}/generated/env/k8s-setup-workers.env"
# }
#
# resource "aws_s3_object" "k8s-setup-workers_env_s3" {
#   bucket = var.k8s_scripts_bucket_name
#   key    = "scripts/controllers/env/k8s-setup-workers.env"
#   source = "${path.module}/generated/env/k8s-setup-workers.env"
#   etag   = filemd5("${path.module}/generated/env/k8s-setup-workers.env")
# }
#
# resource "local_file" "install-cluster-addons_env" {
#   content  = <<-EOT
# CLUSTER_NAME=${local.cluster_name}
# K8S_USER=${local.k8s_user}
# K8S_VERSION=${local.k8s_version}
# SERVICE_CIDR=${local.service_cidr}
# POD_CIDR=${local.pod_cidr}
# NODE_NAME=${local.node_name}
# NODE_ROLE=${local.node_role}
# AWS_REGION=${local.aws_region}
# LOG_LEVEL=${local.log_level}
# EOT
#   filename = "${path.module}/generated/env/install-cluster-addons.env"
# }
#
# resource "aws_s3_object" "install-cluster-addons_env_s3" {
#   bucket = var.k8s_scripts_bucket_name
#   key    = "scripts/controllers/env/install-cluster-addons.env"
#   source = "${path.module}/generated/env/install-cluster-addons.env"
#   etag   = filemd5("${path.module}/generated/env/install-cluster-addons.env")
# }
#
# resource "local_file" "entrypoint_env" {
#   content  = <<-EOT
# CLUSTER_NAME=${local.cluster_name}
# K8S_USER=${local.k8s_user}
# K8S_VERSION=${local.k8s_version}
# SERVICE_CIDR=${local.service_cidr}
# POD_CIDR=${local.pod_cidr}
# NODE_NAME=${local.node_name}
# NODE_ROLE=${local.node_role}
# AWS_REGION=${local.aws_region}
# LOG_LEVEL=${local.log_level}
# EOT
#   filename = "${path.module}/generated/env/entrypoint.env"
# }
#
# resource "aws_s3_object" "entrypoint_env_s3" {
#   bucket = var.k8s_scripts_bucket_name
#   key    = "scripts/controllers/env/entrypoint.env"
#   source = "${path.module}/generated/env/entrypoint.env"
#   etag   = filemd5("${path.module}/generated/env/entrypoint.env")
# }

