# modules/controllers/main.tf
# Kubernetes control plane infrastructure - improved without provisioners

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

#===============================================================================
# Local Values
#===============================================================================

locals {
  # Instance configuration
  on_demand_count = var.on_demand_count
  spot_count      = var.spot_count
  instance_types  = var.instance_types

  # Kubernetes configuration
  cluster_name               = var.cluster_name
  k8s_user                   = var.k8s_user
  k8s_major_minor_stream     = var.k8s_major_minor_stream
  k8s_full_patch_version     = var.k8s_full_patch_version
  k8s_apt_package_suffix     = var.k8s_apt_package_suffix
  k8s_package_version_string = "${var.k8s_full_patch_version}-${var.k8s_apt_package_suffix}"

  # IAM configuration
  control_plane_role_name = var.control_plane_role_name

  # Network configuration
  base_aws_ami       = var.base_aws_ami
  subnet_ids         = var.subnet_ids
  pod_cidr_block     = var.pod_cidr_block
  service_cidr_block = var.service_cidr_block

  # Security configuration
  environment          = var.environment
  ssh_key_name         = var.ssh_key_name
  ssh_public_key_path  = var.ssh_public_key_path
  ssh_private_key_path = var.ssh_private_key_path
  security_group_ids   = var.security_group_ids

  # Calculated values
  total_instance_count = local.on_demand_count + local.spot_count

  # Control plane identification
  controller_tag_key   = "ClusterControllerType"
  controller_tag_value = "${local.cluster_name}-controller"

  # SSM paths
  ssm_join_command_path    = "/entropy-engines/${local.cluster_name}/control-plane/join-command"
  ssm_certificate_key_path = "/entropy-engines/${local.cluster_name}/join-command/certificate/key"

  # Script selection
  control_plane_bootstrap_script     = "control-plane-bootstrap.sh.tftpl"
  control_plane_bootstrap_script_key = "cp-bootstrap.sh"

  # Common tags
  common_tags = merge(var.additional_tags, {
    Cluster     = local.cluster_name
    Environment = local.environment
    NodeType    = "control-plane"
    ManagedBy   = "terraform"
  })
}

#===============================================================================
# Data Sources
#===============================================================================

# Get current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# S3 Bootstrap Script Upload
#===============================================================================

locals {
  # Define each script, its template, and its specific variables
  control_plane_scripts = {
    "01-install-user-and-tooling" = {
      template_path = "${path.module}/templates/install-user-and-tooling.sh.tftpl"
      vars = {
        k8s_user                   = local.k8s_user
        k8s_major_minor_stream     = local.k8s_major_minor_stream
        k8s_package_version_string = local.k8s_package_version_string
      }
    },
    "02-configure-control-plane" = {
      template_path = "${path.module}/templates/configure-control-plane.sh.tftpl"
      vars = {
        node_index               = 0 # revisit for multiple control plane nodes
        cluster_name             = local.cluster_name
        k8s_full_patch_version   = local.k8s_full_patch_version
        pod_cidr_block           = local.pod_cidr_block
        service_cidr_block       = local.service_cidr_block
        ssm_join_command_path    = local.ssm_join_command_path
        ssm_certificate_key_path = local.ssm_certificate_key_path
      }
    },
    "03-k8s-controller-setup" = {
      template_path = "${path.module}/templates/k8s-controller-setup.sh.tftpl",
      vars = {
        k8s_user = local.k8s_user
      }
    },
  }

  rendered_s3_scripts = {
    for key, config in local.control_plane_scripts : key => templatefile(config.template_path, config.vars)
  }
}

resource "aws_s3_object" "control_plane_setup_scripts" {
  for_each = local.rendered_s3_scripts

  bucket = var.bootstrap_bucket_name

  key = "scripts/${each.key}.sh"

  content = each.value

  etag = md5(each.value)

  # depends_on = [var.bootstrap_bucket_dependency]
}

#===============================================================================
# IAM Instance Profile
#===============================================================================

resource "aws_iam_instance_profile" "controller_profile" {
  name = "${local.cluster_name}-controller-profile"
  role = local.control_plane_role_name

  tags = merge(local.common_tags, {
    Name    = "${local.cluster_name}-controller-profile"
    Purpose = "kubernetes-control-plane-instance-profile"
  })
}

#===============================================================================
# Launch Template for Controllers
#===============================================================================

resource "aws_launch_template" "controller_lt" {
  name_prefix = "${local.cluster_name}-controller-lt-"
  description = "Launch template for ${local.cluster_name} Control Plane"

  image_id = local.base_aws_ami
  key_name = local.ssh_key_name

  # User data for self-bootstrapping control plane
  user_data = base64encode(templatefile("${path.module}/templates/entrypoint.sh.tftpl", {
    s3_bucket_name = var.bootstrap_bucket_name
  }))

  iam_instance_profile {
    name = aws_iam_instance_profile.controller_profile.name
  }

  vpc_security_group_ids = local.security_group_ids

  # Block device mappings
  dynamic "block_device_mappings" {
    for_each = var.block_device_mappings
    content {
      device_name = block_device_mappings.value.device_name
      ebs {
        volume_size           = block_device_mappings.value.volume_size
        volume_type           = block_device_mappings.value.volume_type
        delete_on_termination = block_device_mappings.value.delete_on_termination
        encrypted             = block_device_mappings.value.encrypted
        iops                  = block_device_mappings.value.iops
        throughput            = block_device_mappings.value.throughput
        kms_key_id            = block_device_mappings.value.kms_key_id
      }
    }
  }

  # Instance metadata options (force IMDSv2 for security)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  # Enable detailed monitoring
  monitoring {
    enabled = true
  }

  # Define tags that will be applied to instances launched by the fleet
  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name                          = "${local.cluster_name}-controller"
      "${local.controller_tag_key}" = local.controller_tag_value
    })
  }

  # Tags for the launch template itself
  tags = merge(local.common_tags, {
    Name    = "${local.cluster_name}-controller-launch-template"
    Purpose = "kubernetes-control-plane-launch-template"
  })

  lifecycle {
    create_before_destroy = true
  }
}

#===============================================================================
# Auto Scaling Group for Controllers
#===============================================================================

resource "aws_autoscaling_group" "controller_asg" {
  count = local.total_instance_count > 0 ? 1 : 0

  name_prefix      = "${local.cluster_name}-controller-asg-"
  desired_capacity = local.total_instance_count
  min_size         = local.total_instance_count
  max_size         = local.total_instance_count

  # Specify all the subnets where instances can be launched
  vpc_zone_identifier = local.subnet_ids

  # Health check configuration
  health_check_type         = "EC2"
  health_check_grace_period = var.health_check_grace_period
  wait_for_capacity_timeout = var.capacity_timeout

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.controller_lt.id
        version            = "$Latest"
      }

      dynamic "override" {
        for_each = local.instance_types
        content {
          instance_type = override.value
        }
      }
    }

    instances_distribution {
      # Calculate on-demand percentage based on your variables
      on_demand_base_capacity                  = local.on_demand_count
      on_demand_percentage_above_base_capacity = local.on_demand_count > 0 && local.spot_count > 0 ? floor((local.on_demand_count / local.total_instance_count) * 100) : (local.on_demand_count > 0 ? 100 : 0)

      spot_allocation_strategy = var.spot_allocation_strategy
    }
  }

  # Instance refresh for rolling updates
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = var.min_healthy_percentage
      instance_warmup        = 600 # Control plane needs more time to bootstrap
    }
    triggers = ["tag"]
  }

  dynamic "tag" {
    for_each = merge(local.common_tags, {
      Name                          = "${local.cluster_name}-controller-asg"
      "${local.controller_tag_key}" = local.controller_tag_value
    })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_iam_instance_profile.controller_profile,
    aws_s3_object.control_plane_setup_scripts
  ]
}

#===============================================================================
# Data Sources to Fetch Controller Instance Details
#===============================================================================

data "aws_instances" "controllers" {
  instance_tags = {
    "${local.controller_tag_key}" = local.controller_tag_value
  }

  instance_state_names = ["pending", "running"]

  depends_on = [aws_autoscaling_group.controller_asg]
}

#===============================================================================
# SSM Parameters and Configuration
#===============================================================================

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
}
