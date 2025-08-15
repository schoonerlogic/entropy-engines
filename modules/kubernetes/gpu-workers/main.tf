# modules/kubernetes/gpu-workers/main.tf
# GPU-specific wrapper around worker-base

#===============================================================================
# Local Values for GPU Workers
#===============================================================================

locals {
  # Common tags
  common_tags = {
    Cluster     = local.cluster_name
    Environment = local.environment
    NodeType    = "gpu-worker"
    ManagedBy   = "terraform"

    install_nvidia_drivers = true
    gpu_device_plugin      = "nvidia"
  }

  # GPU-specific information that might be useful
  gpu_worker_info = {
    supports_cuda         = var.gpu_type == "nvidia"
    supports_ml_workloads = true
    requires_gpu_drivers  = true
    typical_workloads     = ["machine-learning", "ai-training", "gpu-compute"]
  }
}


# =================================================================
# SCRIPT CONFIGURATION MAPS - GPU WORKERS
# =================================================================

locals {
  # Script base path
  script_base_path = "${path.module}/../s3-setup-scripts"


  # GPU Worker template variables (might have GPU-specific vars)
  cluster_name = var.cluster_name
  environment  = var.environment

  # k8s_setup_main_vars
  k8s_main_setup_main_vars = {
    script_dir = "/tmp/k8s_scripts"
  }

  # shared_functions 
  shared_functions_vars = {
    log_dir   = "/var/log/provisioning"
    log_level = var.log_level
  }

  # Entrypoint variable
  entrypoint_vars = {
    s3_bucket_name = var.k8s_scripts_bucket_name
    node_type      = "workers"
    log_dir        = "/var/log/provisioning"
    script_dir     = "/tmp/k8s_scripts"
  }

  # Template variables for shared scripts
  shared_template_vars = {
    k8s_user                   = var.k8s_user
    k8s_major_minor_stream     = var.k8s_major_minor_stream
    k8s_package_version_string = var.k8s_package_version_string
    script_dir                 = "/tmp/k8s_scripts"
  }

  # Template variables for GPU worker-specific scripts
  gpu_worker_template_vars = merge(local.shared_template_vars, {
    cluster_name          = var.cluster_name
    ssm_join_command_path = var.ssm_join_command_path
    script_dir            = "/tmp/k8s_scripts"
  })


  # Shared scripts (used by both controllers and workers)
  shared_scripts = {
    "00-shared-functions" = {
      template_path = "${local.script_base_path}/shared/00-shared-functions.sh.tftpl"
      vars          = local.shared_functions_vars
      s3_key        = "scripts/workers/00-shared-functions.sh"
    }
    "001-ec2-metadata-lib" = {
      template_path = "${local.script_base_path}/shared/001-ec2-metadata-lib.sh.tftpl"
      vars          = {}
      s3_key        = "scripts/workers/001-ec2-metadata-lib.sh"
    }
    "01-install-user-and-tooling" = {
      template_path = "${local.script_base_path}/shared/01-install-user-and-tooling.sh.tftpl"
      vars          = local.shared_template_vars
      s3_key        = "scripts/workers/01-install-user-and-tooling.sh"
    }
    "entrypoint" = {
      template_path = "${local.script_base_path}/shared/entrypoint.sh.tftpl"
      vars          = local.entrypoint_vars
      s3_key        = "scripts/workers/entrypoint.sh"
    }
  }

  # GPU Worker-specific scripts
  gpu_worker_scripts = {
    "k8s-setup-main" = {
      template_path = "${local.script_base_path}/workers/k8s-setup-main.sh.tftpl"
      vars          = local.k8s_main_setup_main_vars
      s3_key        = "scripts/workers/k8s-setup-main.sh"
    }
    "02-setup-nvme-storage" = {
      template_path = "${local.script_base_path}/workers/02-setup-nvme-storage.sh.tftpl"
      vars          = local.gpu_worker_template_vars
      s3_key        = "scripts/workers/02-setup-nvme-storage.sh"
    }
    "03-join-cluster" = {
      template_path = "${local.script_base_path}/workers/03-join-cluster.sh.tftpl"
      vars          = local.gpu_worker_template_vars
      s3_key        = "scripts/workers/03-join-cluster.sh"
    }
    # # Add GPU-specific scripts if needed
    # "04-setup-gpu-drivers" = {
    #   template_path = "${local.script_base_path}/workers/04-setup-gpu-drivers.sh.tftpl"
    #   vars          = local.gpu_worker_template_vars
    #   s3_key        = "scripts/workers/04-setup-gpu-drivers.sh"
    # }
  }

  all_gpu_worker_scripts = merge(local.shared_scripts, local.gpu_worker_scripts)
}

# =================================================================
# S3 SCRIPT UPLOADS - GPU WORKERS
# =================================================================

resource "aws_s3_object" "gpu_worker_scripts" {
  for_each = local.all_gpu_worker_scripts

  bucket  = var.k8s_scripts_bucket_name
  key     = each.value.s3_key
  content = templatefile(each.value.template_path, each.value.vars)

  content_type = "text/plain"


  # Generate ETag based on content for change detection
  etag = md5(templatefile(each.value.template_path, each.value.vars))

  tags = merge(local.common_tags, {
    Type = "gpu-worker-script"
  })
}

# =================================================================
# WORKER-BASE MODULE REFERENCE
# =================================================================
module "gpu_worker_base" {
  source = "../worker-base"

  # Cluster configuration
  cluster_name = var.cluster_name
  worker_type  = "gpu"
  environment  = var.environment

  # Script bucket configuration
  k8s_scripts_bucket_name = var.k8s_scripts_bucket_name

  # Instance configuration
  instance_types  = var.gpu_instance_types
  on_demand_count = var.gpu_on_demand_count
  spot_count      = var.gpu_spot_count

  # Instance requirements (if using)
  use_instance_requirements = var.use_instance_requirements
  instance_requirements     = var.instance_requirements

  # Infrastructure configuration
  base_aws_ami       = var.base_aws_ami
  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids
  ssh_key_name       = var.ssh_key_name
  worker_role_name   = var.worker_role_name

  # ASG configuration
  min_size                  = var.min_size
  max_size                  = var.max_size
  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period
  capacity_timeout          = var.capacity_timeout

  # Instance distribution
  spot_allocation_strategy = var.spot_allocation_strategy
  min_healthy_percentage   = var.min_healthy_percentage
  instance_warmup          = var.instance_warmup

  # Storage configuration
  block_device_mappings = var.block_device_mappings

  # Tagging
  additional_tags    = var.additional_tags
  iam_policy_version = var.iam_policy_version

  # GPU workers don't have GPU-specific settings
  gpu_type       = null
  gpu_memory_min = null

  script_dependencies = aws_s3_object.gpu_worker_scripts

  # Ensure scripts are uploaded before infrastructure is created
  depends_on = [aws_s3_object.gpu_worker_scripts]
}

# =================================================================
# DATA SOURCES
# =================================================================

# Get current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =================================================================
# OPTIONAL: MONITORING AND NOTIFICATIONS
# =================================================================

# CloudWatch Log Group for GPU worker logs (optional)
resource "aws_cloudwatch_log_group" "gpu_worker_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name              = "/aws/ec2/kubernetes-gpu-workers/${var.cluster_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name    = "${var.cluster_name}-gpu-worker-logs"
    Purpose = "kubernetes-gpu-worker-logging"
  })
}

# SNS Topic for GPU worker notifications (optional)
resource "aws_sns_topic" "gpu_worker_notifications" {
  count = var.enable_notifications ? 1 : 0

  name = "${var.cluster_name}-gpu-worker-notifications"

  tags = merge(local.common_tags, {
    Name    = "${var.cluster_name}-gpu-worker-notifications"
    Purpose = "kubernetes-gpu-worker-notifications"
  })
}

# ASG Notifications (optional)
resource "aws_autoscaling_notification" "gpu_worker_notifications" {
  count = var.enable_notifications && module.gpu_worker_base.asg_name != null ? 1 : 0

  group_names = [module.gpu_worker_base.asg_name]

  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  ]

  topic_arn = aws_sns_topic.gpu_worker_notifications[0].arn
}

