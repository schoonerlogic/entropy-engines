# root - kubernetes.tf
# Controllers Module - No Provisioners, Self-Bootstrapping
module "kubernetes" {
  source = "./modules/kubernetes"

  # Basic Kubernetes config
  cluster_name           = var.kubernetes_config.cluster_name != null ? var.kubernetes_config.cluster_name : var.project_name
  enable_kubernetes_tags = var.kubernetes_config.enable_kubernetes_tags
  enable_nats_messaging  = var.kubernetes_config.enable_nats_messaging
  ssh_private_key_path   = var.kubernetes_config.ssh_private_key_path
  ssh_public_key_path    = var.kubernetes_config.ssh_public_key_path

  # Kubernetes versioning
  k8s_user               = var.kubernetes_config.k8s_user
  k8s_major_minor_stream = var.kubernetes_config.k8s_major_minor_stream
  k8s_full_patch_version = var.kubernetes_config.k8s_full_patch_version
  k8s_apt_package_suffix = var.kubernetes_config.k8s_apt_package_suffix

  # NATS port config
  nats_client_port     = var.kubernetes_config.nats_ports.client
  nats_cluster_port    = var.kubernetes_config.nats_ports.cluster
  nats_leafnode_port   = var.kubernetes_config.nats_ports.leafnode
  nats_monitoring_port = var.kubernetes_config.nats_ports.monitoring

  # SSM paths
  ssm_join_command_path    = var.kubernetes_config.ssm_join.ssm_join_command_path
  ssm_certificate_key_path = var.kubernetes_config.ssm_join.ssm_certificate_key_path

  # # Kubernetes configuration
  # k8s_user                   = var.kubernetes_config.k8s_user
  # k8s_major_minor_stream     = var.kubernetes_config.k8s_major_minor_stream
  # k8s_full_patch_version     = var.kubernetes_config.k8s_full_patch_version
  # k8s_apt_package_suffix     = var.kubernetes_config.k8s_apt_package_suffix
  # k8s_package_version_string = "${var.kubernetes_config.k8s_full_patch_version}-${var.kubernetes_config.k8s_apt_package_suffix}"
  #
  # ssm_join_command_path    = var.kubernetes_config.ssm_join.ssm_join_command_path
  # ssm_certificate_key_path = var.kubernetes_config.ssm_join.ssm_certificate_key_path
  #
  # pod_cidr_block     = var.network_config.pod_cidr_block
  # service_cidr_block = var.network_config.service_cidr_block
  #
  # # Networking
  # subnet_ids         = var.network_config.private_subnet_ids
  # security_group_ids = var.network_config.control_plane_security_group_id
  #
  # # S3
  # k8s_scripts_bucket_name = var.k8s_scripts_bucket_name
  #
  # # SSH 
  # ssh_public_key_path  = var.security_config.ssh_public_key_path
  # ssh_private_key_path = var.security_config.ssh_private_key_path
  #
  # # Storage configuration
  # block_device_mappings = var.instance_config.default_block_device_mappings
  #
  #
  #   on_demand_count = var.k8s_control_plane_config.on_demand_count
  #   spot_count      = var.k8s_control_plane_config.spot_count
  #   instance_types  = var.k8s_control_plane_config.instance_types
  #
  #   control_plane_role_name = var.iam_config.control_plane_role_name
  #
  #
  #
  #
  # pod_cidr_block     = module.aws_infrastructure.pod_cidr_block
  # service_cidr_block = module.aws_infrastructure.service_cidr_block
  #
  # subnet_ids         = module.aws_infrastructure.private_subnet_ids
  # security_group_ids = [module.aws_infrastructure.control_plane_security_group_id]
  #
  # k8s_scripts_bucket_name = module.aws_infrastructure.k8s_scripts_bucket_name
  #
  # control_plane_role_name = var.iam_config.control_plane_role_name
  #
  depends_on = [data.aws_ami.ubuntu]

}



