# Local values for AWS-specific configuration
locals {
  base_ami_id            = var.base_ami_id
  environment            = var.environment
  instance_type          = var.instance_config.instance_type
  on_demand_count        = var.instance_config.on_demand_count
  spot_count             = var.instance_config.spot_count
  instance_types         = var.instance_config.instance_types
  cluster_name           = var.kubernetes_config.cluster_name
  k8s_user               = var.kubernetes_config.k8s_user
  k8s_major_minor_stream = var.kubernetes_config.k8s_major_minor_stream
  k8s_full_patch_version = var.kubernetes_config.k8s_full_patch_version
  k8s_apt_package_suffix = var.kubernetes_config.k8s_apt_package_suffix
  iam_policy_version     = var.network_config.iam_policy_version
  subnet_ids             = var.network_config.subnet_ids
  pod_cidr_block         = var.network_config.kubernetes_cidrs.pod_cidr
  service_cidr_block     = var.network_config.kubernetes_cidrs.service_cidr
  ssh_key_name           = var.security_config.ssh_key_name
  ssh_public_key_path    = var.security_config.ssh_public_key_path
  ssh_private_key_path   = var.security_config.ssh_private_key_path
  security_group_ids     = var.security_config.security_group_ids
  bastion_host           = var.security_config.bastion_host
  bastion_user           = var.security_config.bastion_user
}

locals {
  total_instance_count = local.on_demand_count + local.spot_count
  # Create a map where keys are indices (0, 1, ...) and values are instance IDs
  # The keys are known at plan time based on the list length (derived from instance_count)
  instance_id_map = {
    for idx, inst_id in local.all_instance_ids : idx => inst_id
  }

  k8s_apt_install_version_string = "${local.k8s_full_patch_version}${local.k8s_apt_package_suffix}"

  k8s_user_data = base64encode(templatefile("${path.module}/scripts/control-node-init.sh", {
    ssh_public_key                  = file(pathexpand(local.ssh_public_key_path)),
    k8s_user                        = local.k8s_user,
    k8s_repo_stream_for_apt         = local.k8s_major_minor_stream         # e.g., "1.33"
    k8s_package_version_for_install = local.k8s_apt_install_version_string # e.g., "1.33.1-00"
  }))

  controller_tag_key            = "ClusterControllerType"
  controller_tag_value          = "${local.cluster_name}-controller"
  effective_spot_instance_types = coalescelist(local.instance_types, [local.instance_type])
}


# resource "aws_iam_instance_profile" "controller_profile" {
#   name = "${local.cluster_name}-controller-profile"
#   role = var.aws_config.controller_role_name
# }

# Create Launch Template for Spot Fleet
resource "aws_launch_template" "controller_lt" {

  name_prefix = "${local.cluster_name}-controller-lt-"
  description = "Launch template for ${local.cluster_name} Controller Spot Fleet"
  image_id    = var.aws_config.base_ami_id
  key_name    = var.aws_config.ssh_key_name
  user_data   = base64encode(local.k8s_user_data)

  iam_instance_profile {
    name = aws_iam_instance_profile.controller_profile.name
  }

  vpc_security_group_ids = local.security_group_ids

  # Define tags that will be applied to instances launched by the fleet
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "${local.cluster_name}-controller-fleet"
      Cluster = local.cluster_name

      IamPolicyVersion = local.iam_policy_version
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "controller_asg" {
  count = local.total_instance_count > 0 ? 1 : 0

  name_prefix      = "${local.cluster_name}-controller-asg-"
  desired_capacity = local.total_instance_count
  min_size         = local.total_instance_count
  max_size         = local.total_instance_count

  # Specify all the subnets where instances can be launched
  vpc_zone_identifier = local.subnet_ids

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.controller_lt.id
        version            = "$Latest"
      }

      dynamic "override" {
        for_each = local.effective_spot_instance_types
        content {
          instance_type = override.value
        }
      }
    }

    instances_distribution {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy                 = "capacity-optimized"
    }
  }

  # --- Instance Refresh: The feature you want! ---
  # When the launch template changes, the ASG will automatically and gracefully
  # replace the instances.
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50 # Or whatever percentage you're comfortable with
    }
    triggers = ["tag"] # Refresh if instance tags in the LT change. Can also add "launch_template".
  }

  # This ensures old instances are terminated on destroy
  wait_for_capacity_timeout = "10m"

  dynamic "tag" {
    for_each = {
      Name    = "${local.cluster_name}-controller-asg"
      Cluster = local.cluster_name
    }
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- Data Source to Fetch Controller Instance Details ---
# This fetches details AFTER instances are running and tagged,
# either from aws_instance or launched by the Spot Fleet.
data "aws_instances" "controller" {
  # Filter based on the common tag applied by both aws_instance and the launch template
  instance_tags = {
    "${local.controller_tag_key}" = local.controller_tag_value
  }

  # Filter based on instance state to avoid terminated instances
  instance_state_names = ["pending", "running"]

  depends_on = [
    aws_autoscaling_group.controller_asg
  ]
}

data "aws_instances" "controller_fleet_instances" {

  filter {
    name   = "tag:${local.controller_tag_key}"
    values = [local.controller_tag_value]
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }

  depends_on = [aws_autoscaling_group.controller_asg]
}

locals {
  asg_instance_ips = local.total_instance_count > 0 ? data.aws_instances.controller_fleet_instances.private_ips : []

  asg_instance_ids = local.total_instance_count > 0 ? data.aws_instances.controller_fleet_instances.ids : []

  all_controller_ips = local.asg_instance_ips
  all_instance_ids   = local.asg_instance_ids
}

locals {
  wait_for_kubernetes_install = templatefile("${path.module}/templates/wait-for-kubernetes.sh.tftpl", {})
}

locals {
  bootstrap_script = templatefile("${path.module}/templates/bootstrap.sh.tftpl", {
    k8s_user = local.k8s_user
  })
}

resource "null_resource" "bootstrap_kubernetes_control_plane" {
  count = local.total_instance_count > 0 ? 1 : 0

  triggers = {
    controller_instances  = join(",", local.all_instance_ids)
    bootstrap_script_hash = filebase64sha256("${path.module}/templates/bootstrap.sh.tftpl")
  }

  depends_on = [
    aws_autoscaling_group.controller_asg
  ]

  connection {
    type                = "ssh"
    host                = local.all_controller_ips[0]
    user                = var.k8s_config.k8s_user
    private_key         = file(pathexpand(local.ssh_private_key_path))
    bastion_host        = local.bastion_host
    bastion_user        = local.bastion_user
    bastion_private_key = file(pathexpand(local.ssh_private_key_path))
  }

  provisioner "file" {
    content     = local.bootstrap_script
    destination = "/tmp/bootstrap.sh"
  }
}


# --- Revised kubernetes_control_plane_join ---
resource "null_resource" "kubernetes_control_plane_join" {
  count = local.total_instance_count > 0 ? 1 : 0

  triggers = {
    controller_instances = join(",", local.all_instance_ids)
    bootstrap_id         = null_resource.bootstrap_kubernetes_control_plane[0].id
  }

  # Add dependency on the SSM upload finishing
  depends_on = [
    null_resource.bootstrap_kubernetes_control_plane
  ]

  connection {
    type                = "ssh"
    host                = local.all_controller_ips[count.index]
    user                = var.k8s_config.k8s_user
    private_key         = file(pathexpand(local.ssh_private_key_path))
    bastion_host        = local.bastion_host
    bastion_user        = local.bastion_user
    bastion_private_key = file(pathexpand(local.ssh_private_key_path))
  }

  provisioner "file" {
    content = templatefile("${path.module}/templates/configure-controller.sh.tftpl", {
      # --- Pass all required ariables into the template ---
      node_index            = count.index
      is_primary_controller = count.index == 0
      primary_controller_ip = local.all_controller_ips[0]

      k8s_full_patch_version = var.k8s_config.k8s_full_patch_version
      pod_cidr_block         = local.pod_cidr_block
      service_cidr_block     = local.service_cidr_block

      ssm_join_command_path    = local.ssm_join_command_path
      ssm_certificate_key_path = local.ssm_certificate_key_path
    })
    destination = "/tmp/configure-controller.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/wait-for-kubernetes.sh",
      "sudo bash /tmp/configure-controller.sh"
    ]
  }
}

# Wait for Kubernetes installation to complete on all controllers
resource "null_resource" "wait_for_kubernetes_install" {
  count = local.total_instance_count > 0 ? 1 : 0

  triggers = {
    # Recreate when controller instances change
    controller_instances = join(",", local.all_instance_ids)
    controller_ips       = join(",", local.all_controller_ips)
  }

  depends_on = [
    aws_autoscaling_group.controller_asg,
  ]

  connection {
    type                = "ssh"
    host                = local.all_controller_ips[count.index]
    user                = var.k8s_config.k8s_user
    private_key         = file(pathexpand(local.ssh_private_key_path))
    bastion_host        = local.bastion_host
    bastion_user        = local.bastion_user
    bastion_private_key = file(pathexpand(local.ssh_private_key_path))

  }

  provisioner "file" {
    content     = local.wait_for_kubernetes_install
    destination = "/tmp/wait-for-kubernetes.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/wait-for-kubernetes.sh",
      "sudo bash /tmp/wait-for-kubernetes.sh"
    ]
  }

}
locals {
  cluster_addons = templatefile("${path.module}/templates/cluster-addons.sh.tftpl", {})
}

# --- NEW Resource to Apply Cluster Addons ---
resource "null_resource" "apply_cluster_addons" {
  count = local.total_instance_count > 0 ? 1 : 0

  triggers = {
    # Recreate when controller instances change
    controller_instances = join(",", local.all_instance_ids)
    controller_ips       = join(",", local.all_controller_ips)
    # Optional: trigger on bootstrap completion
    bootstrap_id = null_resource.bootstrap_kubernetes_control_plane[0].id
  }

  # IMPORTANT: Depend on the bootstrap resource finishing successfully
  depends_on = [
    null_resource.kubernetes_control_plane_join
  ]


  # Connect specifically to the FIRST instance (same as bootstrap)
  connection {
    type                = "ssh"
    host                = local.all_controller_ips[0]
    user                = var.k8s_config.k8s_user
    private_key         = file(pathexpand(local.ssh_private_key_path))
    bastion_host        = local.bastion_host
    bastion_user        = local.bastion_user
    bastion_private_key = file(pathexpand(local.ssh_private_key_path))
  }

  provisioner "file" {
    content     = local.cluster_addons
    destination = "/tmp/cluster-addons.sh"
  }

  # Provisioner to run the addon application commands
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/cluster-addons.sh",
      "sudo bash /tmp/cluster-addons.sh"
    ]
  }
}

locals {
  upload_join_command = templatefile("${path.module}/templates/upload-join-command.tftpl", {
    ssm_join_command_path    = local.ssm_join_command_path,
    ssm_certificate_key_path = local.ssm_certificate_key_path
  })
}


resource "null_resource" "upload_join_info_to_ssm" {
  count = local.total_instance_count > 0 ? 1 : 0

  triggers = {
    # Recreate when controller instances change
    controller_instances = join(",", local.all_instance_ids)
    controller_ips       = join(",", local.all_controller_ips)
    # Optional: trigger on bootstrap completion
    bootstrap_id = null_resource.bootstrap_kubernetes_control_plane[0].id
    script_hash  = sha1(local.upload_join_command)
  }

  # Depend on the bootstrap finishing (which creates the files)
  depends_on = [
    null_resource.kubernetes_control_plane_join,
    null_resource.apply_cluster_addons
  ]

  connection {
    type                = "ssh"
    host                = local.all_controller_ips[0]
    user                = var.k8s_config.k8s_user
    private_key         = file(pathexpand(local.ssh_private_key_path))
    bastion_host        = local.bastion_host
    bastion_user        = local.bastion_user
    bastion_private_key = file(pathexpand(local.ssh_private_key_path))
  }

  provisioner "file" {
    content     = local.upload_join_command
    destination = "/tmp/upload-join-command.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Join files verified. Running upload script...'",
      "chmod +x /tmp/upload-join-command.sh",
      "sudo bash /tmp/upload-join-command.sh"
    ]
  }
}

data "aws_caller_identity" "current" {
  # This data source requires no configuration arguments.
}

locals {

  defined_ssm_parameters_suffixes = [
    "/join-command/certificate/key",
    "/control-plane/join-command"
  ]

  # Build the full SSM parameter paths by prepending a static prefix and the cluster name.
  ssm_parameters = [
    for suffix in local.defined_ssm_parameters_suffixes : "entropy-engines/${local.cluster_name}${suffix}"
  ]

  # Create ARNs for each SSM parameter path.
  ssm_parameters_arns = [
    for param in local.ssm_parameters :
    "arn:aws:ssm:${local.environment}:${data.aws_caller_identity.current.account_id}:parameter/${param}"
  ]

  ssm_kms_arn = "arn:aws:kms:${local.environment}:${data.aws_caller_identity.current.account_id}:alias/aws/ssm"

  ssm_join_command_path    = "/entropy-engines/${local.cluster_name}/control-plane/join-command"
  ssm_certificate_key_path = "/entropy-engines/${local.cluster_name}/join-command/certificate/key"
}

