# modules/controllers/main.tf
# Kubernetes control plane infrastructure - improved without provisioners

locals {
  # Kubernetes configuration
  cluster_name               = var.cluster_name
  k8s_user                   = var.k8s_user
  k8s_major_minor_stream     = var.k8s_major_minor_stream
  k8s_full_patch_version     = var.k8s_full_patch_version
  k8s_package_version_string = var.k8s_package_version_string

  # Instance configuration
  on_demand_count = var.on_demand_count
  spot_count      = var.spot_count
  instance_types  = var.instance_types

  # IAM configuration
  control_plane_role_name = var.control_plane_role_name

  # Network configuration
  aws_ami            = var.aws_ami
  subnet_ids         = var.subnet_ids
  pod_cidr_block     = var.pod_cidr_block
  service_cidr_block = var.service_cidr_block

  # Security configuration
  environment          = var.environment
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
  scripts_bucket_name = var.k8s_scripts_bucket_name

  # Script selection
  control_plane_bootstrap_script     = "control-plane-bootstrap.sh"
  control_plane_bootstrap_script_key = "cp-bootstrap.sh"

  common_tags = merge(var.additional_tags, {
    Cluster     = local.cluster_name
    Environment = local.environment
    NodeType    = "control-plane"
    ManagedBy   = "terraform"
  })
}

#===============================================================================
# Data Sourcesu
#===============================================================================

# Get current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# S3 Bootstrap Script Upload
#===============================================================================

locals {
  # Script base path
  script_base_path = "${path.module}/../s3-setup-scripts"

  # shared_functions 
  shared_functions_vars = {
    log_dir   = "/var/log/provisioning"
    log_level = var.log_level
  }

  # entrypoint_vars 
  entrypoint_vars = {
    s3_bucket_name = local.scripts_bucket_name
    node_type      = "controllers"
    log_dir        = "/var/log/provisioning"
    script_dir     = "/tmp/k8s_scripts"
  }

  # k8s_setup_main_vars
  k8s_setup_main_vars = {
    script_dir = "/tmp/k8s_scripts"
  }

  # Shared template variables
  shared_template_vars = {
    k8s_user                   = local.k8s_user
    k8s_major_minor_stream     = local.k8s_major_minor_stream
    k8s_package_version_string = local.k8s_package_version_string
    script_dir                 = "/tmp/k8s_scripts"
  }

  # Controller-specific template variables
  controller_template_vars = merge(local.shared_template_vars, {
    cluster_name             = local.cluster_name
    k8s_full_patch_version   = local.k8s_full_patch_version
    pod_cidr_block           = local.pod_cidr_block
    service_cidr_block       = local.service_cidr_block
    ssm_join_command_path    = local.ssm_join_command_path
    ssm_certificate_key_path = local.ssm_certificate_key_path
    aws_region               = data.aws_region.current.name
    bucket_name              = local.scripts_bucket_name
    wait_interval            = 15
    script_dir               = "/tmp/k8s_scripts"
  })

  # Shared scripts (used by controllers)
  shared_scripts = {
    "00-shared-functions" = {
      script_path = "${local.script_base_path}/shared/00-shared-functions.sh"
      vars        = local.shared_functions_vars
      s3_key      = "scripts/controllers/00-shared-functions.sh"
    }
    "001-ec2-metadata-lib" = {
      script_path = "${local.script_base_path}/shared/001-ec2-metadata-lib.sh"
      vars        = {}
      s3_key      = "scripts/controllers/001-ec2-metadata-lib.sh"
    }
    "01-install-user-and-tooling" = {
      script_path = "${local.script_base_path}/shared/01-install-user-and-tooling.sh"
      vars        = local.shared_template_vars
      s3_key      = "scri/controllerpts/controllers/01-install-user-and-tooling.sh"
    }
    "entrypoint" = {
      script_path = "${local.script_base_path}/shared/entrypoint.sh"
      vars        = local.entrypoint_vars
      s3_key      = "scripts/controllers/entrypoint.sh"
    }
  }

  # Controller-specific scripts
  controller_scripts = {
    "k8s-setup-main" = {
      script_path = "${local.script_base_path}/controllers/k8s-setup-main.sh"
      vars        = local.k8s_setup_main_vars
      s3_key      = "scripts/controllers/k8s-setup-main.sh"
    }
    "02-install-kubernetes" = {
      script_path = "${local.script_base_path}/controllers/02-install-kubernetes.sh"
      vars        = local.controller_template_vars
      s3_key      = "scripts/controllers/02-install-kubernetes.sh"
    }
    "03-install-cni" = {
      script_path = "${local.script_base_path}/controllers/04-install-cni.sh"
      vars        = local.controller_template_vars
      s3_key      = "scripts/controllers/04-install-cni.sh"
    }
    "04-install-addons" = {
      script_path = "${local.script_base_path}/controllers/05-install-addons.sh"
      vars        = local.controller_template_vars
      s3_key      = "scripts/controllers/05-install-addons.sh"
    }
  }

  # Combined for upload
  all_controller_scripts = merge(local.shared_scripts, local.controller_scripts)
}

# Upload controller scripts
resource "aws_s3_object" "controller_scripts" {
  for_each = local.all_controller_scripts

  bucket  = local.scripts_bucket_name
  key     = each.value.s3_key
  content = file(each.value.script_path)

  content_type = "text/plain"

  etag = filemd5(each.value.script_path)

  tags = merge(local.common_tags, {
    Type = "controller-script"
  })

}

# Upload env files
resource "aws_s3_object" "controller_env_files" {
  for_each = local.all_env_files

  bucket  = local.scripts_bucket_name
  key     = each.value.s3_key
  content = each.value.content

  content_type = "text/plain"
  etag         = md5(each.value.content)

  tags = merge(local.common_tags, {
    Type = "env-vars"
  })
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

  image_id = local.aws_ami

  # User data with script dependencies hash
  user_data = base64encode(
    local.shared_scripts.entrypoint.script_path,
    merge(local.shared_scripts.entrypoint.vars, {
      # Force new template when scripts change
      scripts_hash = var.script_dependencies != {} ? md5(jsonencode([
        for k, v in var.script_dependencies : v.etag
        ])) : md5(jsonencode([
        for k, v in aws_s3_object.controller_scripts : v.etag
      ]))
    })
  )

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
    aws_s3_object.controller_scripts
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
