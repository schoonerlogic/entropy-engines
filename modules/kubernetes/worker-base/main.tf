# modules/worker-base/main.tf
# Common worker infrastructure - used by both CPU and GPU worker modules
# Script management removed - now handled by cpu-workers/ and gpu-workers/ modules

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
  # Worker identification tags
  worker_tag_key   = "ClusterWorkerType"
  worker_tag_value = "${var.cluster_name}-${var.worker_type}-worker"

  # ASG sizing (use provided values or default to total count)
  asg_min_size = var.min_size != null ? var.min_size : local.total_instance_count
  asg_max_size = var.max_size != null ? var.max_size : local.total_instance_count

  # Determine if we're using instance requirements or traditional instance types
  using_instance_requirements = var.use_instance_requirements && var.instance_requirements != null

  # Instance configuration
  on_demand_count = var.on_demand_count
  spot_count      = var.spot_count
  instance_types  = var.instance_types

  # Basic configuration
  cluster_name = var.cluster_name
  environment  = var.environment

  # Network configuration
  aws_ami    = var.aws_ami
  subnet_ids = var.subnet_ids

  # Security configuration
  ssh_key_name       = var.ssh_key_name
  security_group_ids = var.security_group_ids

  # Calculated values
  total_instance_count = local.on_demand_count + local.spot_count

  # Common tags
  common_tags = merge(var.additional_tags, {
    Cluster     = local.cluster_name
    Environment = local.environment
    NodeType    = "${var.worker_type}-worker"
    ManagedBy   = "terraform"
  })
}

#===============================================================================
# Data Sources
#===============================================================================

# Get current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

#===============================================================================
# IAM Instance Profile
#===============================================================================
resource "aws_iam_instance_profile" "worker_profile" {
  name = "${var.cluster_name}-${var.worker_type}-worker-profile"
  role = var.worker_role_name

  tags = merge(local.common_tags, {
    Name    = "${var.cluster_name}-${var.worker_type}-worker-profile"
    Purpose = "kubernetes-worker-instance-profile"
  })
}

#===============================================================================
# Launch Template
#===============================================================================
resource "aws_launch_template" "worker_lt" {
  name_prefix = "${var.cluster_name}-${var.worker_type}-worker-lt-"
  description = "Launch template for ${var.cluster_name} ${var.worker_type} workers"

  # Instance configuration
  image_id = var.base_aws_ami
  key_name = var.ssh_key_name

  # User data with script dependencies hash
  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh.tftpl", {
    s3_bucket_name = var.k8s_scripts_bucket_name
    node_type      = "worker"
    script_prefix  = "workers"
    # Force new template when scripts change
    scripts_hash = var.script_dependencies != {} ? md5(jsonencode([
      for k, v in var.script_dependencies : v.etag
    ])) : timestamp()
  }))

  iam_instance_profile {
    name = aws_iam_instance_profile.worker_profile.name
  }

  vpc_security_group_ids = var.security_group_ids

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

  # Tags for instances launched from this template
  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name                      = "${var.cluster_name}-${var.worker_type}-worker"
      IamPolicyVersion          = var.iam_policy_version
      "${local.worker_tag_key}" = local.worker_tag_value
      # GPU-specific tags (null for CPU workers)
      GPUType      = var.gpu_type
      GPUMemoryMin = var.gpu_memory_min != null ? tostring(var.gpu_memory_min) : null
    })
  }

  # Tags for the launch template resource itself
  tags = merge(local.common_tags, {
    Name    = "${var.cluster_name}-${var.worker_type}-worker-launch-template"
    Purpose = "kubernetes-worker-launch-template"
  })

  lifecycle {
    create_before_destroy = true
  }
}

#===============================================================================
# Auto Scaling Group
#===============================================================================

resource "aws_autoscaling_group" "worker_asg" {
  count = local.total_instance_count > 0 ? 1 : 0

  name_prefix      = "${var.cluster_name}-${var.worker_type}-worker-asg-"
  desired_capacity = local.total_instance_count
  min_size         = local.asg_min_size
  max_size         = local.asg_max_size

  vpc_zone_identifier = var.subnet_ids

  # Health check configuration
  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period

  # Wait for capacity timeout
  wait_for_capacity_timeout = var.capacity_timeout

  # Mixed instances policy (supports both traditional types and instance requirements)
  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.worker_lt.id
        version            = "$Latest"
      }

      # Traditional instance type overrides (only if NOT using instance requirements)
      dynamic "override" {
        for_each = local.using_instance_requirements ? [] : var.instance_types
        content {
          instance_type = override.value
        }
      }

      # Instance requirements (only if using instance requirements)
      dynamic "override" {
        for_each = local.using_instance_requirements ? [var.instance_requirements] : []
        content {
          instance_requirements {
            # Required attributes - these must always be present
            vcpu_count {
              min = override.value.vcpu_count.min
              max = override.value.vcpu_count.max
            }
            memory_mib {
              min = override.value.memory_mib.min
              max = override.value.memory_mib.max
            }

            # Only include optional fields that you're actually passing in
            # Remove these lines if you're not using them:

            # Uncomment only if you're passing these in your var.instance_requirements:
            # cpu_architectures = try(override.value.cpu_architectures, null)
            # instance_categories = try(override.value.instance_categories, null)
            # burstable_performance = try(override.value.burstable_performance, null)
          }
        }
      }
    }

    instances_distribution {
      on_demand_base_capacity                  = var.on_demand_count
      on_demand_percentage_above_base_capacity = local.on_demand_count > 0 && local.spot_count > 0 ? floor((local.on_demand_count / local.total_instance_count) * 100) : (local.on_demand_count > 0 ? 100 : 0)
      spot_allocation_strategy                 = var.spot_allocation_strategy
    }
  }

  # Instance refresh for rolling updates
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = var.min_healthy_percentage
      instance_warmup        = var.instance_warmup
    }
  }

  # ASG tags
  dynamic "tag" {
    for_each = merge(local.common_tags, {
      Name                      = "${var.cluster_name}-${var.worker_type}-worker-asg"
      "${local.worker_tag_key}" = local.worker_tag_value
      Purpose                   = "kubernetes-worker-asg"
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
    aws_iam_instance_profile.worker_profile,
  ]
}

#===============================================================================
# Data Source to Get Worker Instances After Creation
#===============================================================================

data "aws_instances" "workers" {
  instance_tags = {
    "${local.worker_tag_key}" = local.worker_tag_value
  }

  instance_state_names = ["pending", "running"]

  depends_on = [aws_autoscaling_group.worker_asg]
}
