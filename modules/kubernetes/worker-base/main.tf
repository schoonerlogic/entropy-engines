# modules/worker-base/main.tf
# Common worker infrastructure - used by both CPU and GPU worker modules

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
  # Calculate total instance count
  total_instance_count = var.on_demand_count + var.spot_count

  # Worker identification tags
  worker_tag_key   = "ClusterWorkerType"
  worker_tag_value = "${var.cluster_name}-${var.worker_type}-worker"

  # Bootstrap script selection - use provided name or default based on worker type
  bootstrap_script_name = var.bootstrap_script_name != null ? var.bootstrap_script_name : "${var.worker_type}-node-init.sh"
  bootstrap_script_path = "${path.module}/scripts/${local.bootstrap_script_name}"

  # ASG sizing (use provided values or default to total count)
  asg_min_size = var.min_size != null ? var.min_size : local.total_instance_count
  asg_max_size = var.max_size != null ? var.max_size : local.total_instance_count

  # Determine if we're using instance requirements or traditional instance types
  using_instance_requirements = var.use_instance_requirements && var.instance_requirements != null

  # On-demand percentage calculation for mixed instances policy
  on_demand_percentage = (
    local.total_instance_count == 0 ? 0 :
    var.on_demand_count == 0 ? 0 :
    var.spot_count == 0 ? 100 :
    floor((var.on_demand_count / local.total_instance_count) * 100)
  )

  # Common tags for all resources
  common_tags = merge(var.additional_tags, {
    Cluster    = var.cluster_name
    WorkerType = var.worker_type
    ManagedBy  = "terraform"
    Module     = "worker-base"
  })
}
#===============================================================================
# Data Sources
#===============================================================================

# Get current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

#===============================================================================
# S3 Bootstrap Script Upload
#===============================================================================

resource "aws_s3_object" "worker_script" {
  bucket = var.bootstrap_bucket_name
  key    = "scripts/${var.cluster_name}/${var.worker_type}-bootstrap-script"
  source = local.bootstrap_script_path

  depends_on = [var.bootstrap_bucket_dependency]

  # Ensure Terraform replaces the object if the file content changes
  etag = filemd5(local.bootstrap_script_path)

  # Set content type for clarity
  content_type = "text/x-shellscript"
}

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
  image_id      = var.base_ami
  instance_type = local.using_instance_requirements ? null : var.instance_types[0]
  key_name      = var.ssh_key_name

  vpc_security_group_ids = var.security_group_ids

  iam_instance_profile {
    name = aws_iam_instance_profile.worker_profile.name
  }

  # User data for self-bootstrapping
  user_data = base64encode(templatefile("${path.module}/templates/user-data.sh.tftpl", {
    s3_script_uri         = "s3://${var.bootstrap_bucket_name}/${aws_s3_object.worker_script.key}"
    k8s_user              = var.k8s_user
    k8s_major_minor       = var.k8s_major_minor_stream
    ssm_join_command_path = "/entropy-engines/${var.cluster_name}/control-plane/join-command"
    cluster_dns_ip        = var.cluster_dns_ip
    cluster_name          = var.cluster_name
  }))

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
      on_demand_percentage_above_base_capacity = local.on_demand_percentage
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
    aws_s3_object.worker_script
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

#===============================================================================
# SSM Parameters (for reference and outputs)
#===============================================================================

locals {
  # SSM parameter paths that the bootstrap scripts will use
  ssm_parameter_paths = [
    "/entropy-engines/${var.cluster_name}/join-command/certificate/key",
    "/entropy-engines/${var.cluster_name}/control-plane/join-command"
  ]

  # Create ARNs for each SSM parameter path (useful for IAM policies)
  ssm_parameter_arns = [
    for param in local.ssm_parameter_paths :
    "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${param}"
  ]

  # SSM KMS key ARN (useful for IAM policies)
  ssm_kms_arn = "arn:aws:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:alias/aws/ssm"
}
