# modules/kubernetes/main.tf
##############################
# Shared Locals
##############################
# Get current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Add the missing Ubuntu AMI data source
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-${var.instance_config.ubuntu_version}-*-${var.instance_config.ami_architecture}-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  environment = var.core_config.environment
  aws_ami     = var.aws_ami

  k8s_user                   = var.kubernetes_config.k8s_user
  cluster_name               = coalesce(var.cluster_name, var.kubernetes_config.cluster_name, "${var.core_config.project}-${var.core_config.environment}")
  k8s_major_minor_stream     = var.kubernetes_config.k8s_major_minor_stream
  k8s_full_patch_version     = var.kubernetes_config.k8s_full_patch_version
  k8s_apt_package_suffix     = var.kubernetes_config.k8s_apt_package_suffix
  k8s_package_version_string = "${var.kubernetes_config.k8s_full_patch_version}-${var.kubernetes_config.k8s_apt_package_suffix}"

  ssm_join_command_path    = var.kubernetes_config.ssm_join.ssm_join_command_path
  ssm_certificate_key_path = var.kubernetes_config.ssm_join.ssm_certificate_key_path

  pod_cidr_block     = var.pod_cidr_block
  service_cidr_block = var.service_cidr_block

  subnet_ids         = coalesce(var.network_config.private_subnet_ids, var.subnet_ids)
  security_group_ids = coalesce(var.network_config.control_plane_security_group_id, var.security_group_ids)

  # S3
  k8s_scripts_bucket_name = var.k8s_scripts_bucket_name

  # SSH 
  ssh_public_key_path  = var.security_config.ssh_public_key_path
  ssh_private_key_path = var.security_config.ssh_private_key_path

  # Storage configuration
  block_device_mappings = var.instance_config.default_block_device_mappings
}

##############################
# Controller Nodes Submodule
##############################
locals {
  ctrl_config = {
    on_demand_count = var.k8s_control_plane_config.on_demand_count
    spot_count      = var.k8s_control_plane_config.spot_count
    instance_types  = var.k8s_control_plane_config.instance_types

    control_plane_role_name = var.iam_config.control_plane_role_name

    # ASG configuration 
    asg_config = {
      health_check_grace_period = 600   # Longer for control plane bootstrap
      min_healthy_percentage    = 49    # Standard for control plane
      capacity_timeout          = "20m" # Longer timeout for control plane
    }

    # Spot configuration 
    spot_allocation_strategy = "capacity-optimized"
    spot_instance_pools      = 2

    pod_cidr_block     = local.pod_cidr_block
    service_cidr_block = local.service_cidr_block

    block_device_mappings = var.k8s_control_plane_config.block_device_mappings
  }
}

module "controllers" {
  source = "./controllers"

  # Core configuration
  cluster_name = local.cluster_name
  environment  = local.environment

  # Instance configuration
  on_demand_count = local.ctrl_config.on_demand_count
  spot_count      = local.ctrl_config.spot_count
  instance_types  = local.ctrl_config.instance_types

  aws_ami = local.aws_ami

  # Kubernetes configuration
  k8s_user                   = local.k8s_user
  k8s_major_minor_stream     = local.k8s_major_minor_stream
  k8s_full_patch_version     = local.k8s_full_patch_version
  k8s_apt_package_suffix     = local.k8s_apt_package_suffix
  k8s_package_version_string = local.k8s_package_version_string
  pod_cidr_block             = local.ctrl_config.pod_cidr_block
  service_cidr_block         = local.ctrl_config.service_cidr_block

  ssm_join_command_path    = local.ssm_join_command_path
  ssm_certificate_key_path = local.ssm_certificate_key_path

  # Networking
  subnet_ids         = local.subnet_ids
  security_group_ids = local.security_group_ids

  # IAM
  control_plane_role_name = local.ctrl_config.control_plane_role_name

  # S3
  k8s_scripts_bucket_name = local.k8s_scripts_bucket_name

  # SSH 
  ssh_public_key_path  = local.ssh_public_key_path
  ssh_private_key_path = local.ssh_private_key_path

  # Storage configuration
  block_device_mappings = coalesce(
    local.ctrl_config.block_device_mappings,
    local.block_device_mappings
  )

  # ASG configuration 
  health_check_grace_period = local.ctrl_config.asg_config.health_check_grace_period
  min_healthy_percentage    = local.ctrl_config.asg_config.min_healthy_percentage
  capacity_timeout          = local.ctrl_config.asg_config.capacity_timeout

  # Spot configuration 
  spot_allocation_strategy = "capacity-optimized"
  spot_instance_pools      = 2

  # Tags
  additional_tags = {
    Environment  = local.environment
    CostCenter   = "infrastructure"
    Criticality  = "high"
    BackupPolicy = "daily"
  }
}

##############################
# CPU Workers Submodule
##############################

locals {
  cpu_config = {
    worker_type = "cpu"
    log_level   = "INFO"

    aws_ami = local.aws_ami
    instance_types = length(var.worker_config.instance_types) > 0 ? var.worker_config.instance_types : [
      "c6i.large", "c6i.xlarge", "c5.large", "c5.xlarge", "m6i.large", "m6i.xlarge"
    ]

    use_instance_requirements = var.worker_config.instance_requirements != null
    instance_requirements = var.worker_config.instance_requirements != null ? merge(
      var.worker_config.instance_requirements,
      {
        # CPU-specific overrides
        instance_categories       = coalesce(var.worker_config.instance_requirements.instance_categories, ["general-purpose", "compute-optimized"])
        burstable_performance     = coalesce(var.worker_config.instance_requirements.burstable_performance, "included")
        accelerator_count         = null # CPU workers don't need GPUs
        accelerator_manufacturers = []
        accelerator_names         = []
        accelerator_types         = []
      }
    ) : null

    # Instance counts
    on_demand_count = var.worker_config.cpu_workers.on_demand_count
    spot_count      = var.worker_config.cpu_workers.spot_count
    total_count     = var.worker_config.cpu_workers.on_demand_count + var.worker_config.cpu_workers.spot_count

    # ASG configuration with CPU-optimized defaults
    asg_config = {
      min_size                  = var.worker_config.asg_config.min_size
      max_size                  = var.worker_config.asg_config.max_size
      health_check_type         = var.worker_config.asg_config.health_check_type
      health_check_grace_period = coalesce(var.worker_config.asg_config.health_check_grace_period, 300) # CPU workers boot faster
      min_healthy_percentage    = coalesce(var.worker_config.asg_config.min_healthy_percentage, 50)     # Standard for CPU
      instance_warmup           = coalesce(var.worker_config.asg_config.instance_warmup, 180)           # Faster warmup
      capacity_timeout          = var.worker_config.asg_config.capacity_timeout
      instance_refresh_triggers = var.worker_config.asg_config.instance_refresh_triggers
    }

    worker_role_name = coalesce(
      var.iam_config.cpu_worker_role_name,
      var.iam_config.worker_role_name,
      var.iam_config.control_plane_role_name,
      "${local.cluster_name}-cpu-worker-role"
    )

    # Spot configuration with CPU-optimized defaults
    spot_allocation_strategy = coalesce(var.worker_config.spot_config.spot_allocation_strategy, "capacity-optimized")
    spot_instance_pools      = coalesce(var.worker_config.spot_config.spot_instance_pools, 4) # More pools for better availability

    # Storage configuration - use base defaults (CPU workers are lightweight)
    block_device_mappings = coalesce(
      var.worker_config.worker_storage_overrides.block_device_mappings,
      var.instance_config.default_block_device_mappings
    )
  }
}

module "cpu_workers" {
  # Only create if CPU workers are configured
  count = local.cpu_config.total_count > 0 ? 1 : 0

  source = "./cpu-workers"

  cluster_name            = local.cluster_name
  log_level               = local.cpu_config.log_level
  k8s_scripts_bucket_name = local.k8s_scripts_bucket_name

  aws_ami                   = local.cpu_config.aws_ami
  use_instance_requirements = local.cpu_config.use_instance_requirements

  subnet_ids         = local.subnet_ids
  security_group_ids = local.security_group_ids

  ssm_join_command_path      = local.ssm_join_command_path
  k8s_user                   = local.k8s_user
  k8s_major_minor_stream     = local.k8s_major_minor_stream
  k8s_package_version_string = local.k8s_package_version_string

  # ASG configuration with CPU-optimized defaults
  min_size                  = local.cpu_config.asg_config.min_size
  max_size                  = local.cpu_config.asg_config.max_size
  health_check_type         = local.cpu_config.asg_config.health_check_type
  health_check_grace_period = local.cpu_config.asg_config.health_check_grace_period
  min_healthy_percentage    = local.cpu_config.asg_config.min_healthy_percentage
  instance_warmup           = local.cpu_config.asg_config.instance_warmup
  capacity_timeout          = local.cpu_config.asg_config.capacity_timeout

  # Spot configuration with CPU-optimized defaults
  spot_allocation_strategy = local.cpu_config.spot_allocation_strategy

  # Storage configuration - use base defaults (CPU workers are lightweight)
  block_device_mappings = local.cpu_config.block_device_mappings

  # Worker role
  worker_role_name = local.cpu_config.worker_role_name

  # Tags
  additional_tags = merge(
    {
      WorkerType  = "cpu"
      Environment = local.environment
      CostTier    = "standard"
    },
    var.worker_config.additional_tags
  )
}

##############################
# GPU Workers Submodule
##############################

locals {
  gpu_config = {
    worker_type = "gpu"
    log_level   = "INFO"

    instance_types = length(var.worker_config.instance_types) > 0 ? var.worker_config.instance_types : [
      "g5.xlarge", "g5.2xlarge", "g5.4xlarge", "g4dn.xlarge", "g4dn.2xlarge", "g4dn.4xlarge"
    ]

    # Instance requirements with GPU-specific defaults
    use_instance_requirements = var.worker_config.instance_requirements != null
    instance_requirements = var.worker_config.instance_requirements != null ? merge(
      var.worker_config.instance_requirements,
      {
        # GPU-specific overrides
        instance_categories   = coalesce(var.worker_config.instance_requirements.instance_categories, ["accelerated-computing"])
        burstable_performance = "excluded" # GPU instances aren't burstable

        # GPU requirements (use config values or sensible defaults)
        accelerator_count = coalesce(
          var.worker_config.instance_requirements.accelerator_count,
          { min = 1, max = 4 }
        )
        accelerator_manufacturers = (length(var.worker_config.instance_requirements.accelerator_manufacturers) > 0 ?
        var.worker_config.instance_requirements.accelerator_manufacturers : ["nvidia"])
        accelerator_types = (length(var.worker_config.instance_requirements.accelerator_types) > 0 ?
        var.worker_config.instance_requirements.accelerator_types : ["gpu"])

        # GPU workloads need high network performance
        network_bandwidth_gbps = coalesce(
          var.worker_config.instance_requirements.network_bandwidth_gbps,
          { min = 10, max = null }
        )
      }
    ) : null

    # Instance counts
    on_demand_count = var.worker_config.gpu_workers.on_demand_count
    spot_count      = var.worker_config.gpu_workers.spot_count
    total_count     = var.worker_config.gpu_workers.on_demand_count + var.worker_config.gpu_workers.spot_count

    # ASG configuration with GPU-optimized defaults (using gpu_asg_overrides)
    asg_config = {
      min_size          = var.worker_config.asg_config.min_size
      max_size          = var.worker_config.asg_config.max_size
      health_check_type = var.worker_config.asg_config.health_check_type

      # Apply GPU-specific overrides or use base config
      health_check_grace_period = coalesce(
        var.worker_config.gpu_config.gpu_asg_overrides.health_check_grace_period,
        var.worker_config.asg_config.health_check_grace_period,
        600 # Longer for GPU drivers
      )
      min_healthy_percentage = coalesce(
        var.worker_config.gpu_config.gpu_asg_overrides.min_healthy_percentage,
        var.worker_config.asg_config.min_healthy_percentage,
        25 # Lower due to high cost
      )
      instance_warmup = coalesce(
        var.worker_config.gpu_config.gpu_asg_overrides.instance_warmup,
        var.worker_config.asg_config.instance_warmup,
        600 # GPU initialization time
      )
      capacity_timeout          = var.worker_config.asg_config.capacity_timeout
      instance_refresh_triggers = var.worker_config.asg_config.instance_refresh_triggers
    }

    # Spot configuration with GPU-optimized defaults
    spot_allocation_strategy = coalesce(var.worker_config.spot_config.spot_allocation_strategy, "capacity-optimized")
    spot_instance_pools = coalesce(
      var.worker_config.gpu_config.gpu_asg_overrides.spot_instance_pools,
      var.worker_config.spot_config.spot_instance_pools,
      2 # Fewer pools but more stable for GPU
    )

    # Storage configuration - use GPU overrides or base config
    block_device_mappings = (length(var.worker_config.gpu_config.gpu_storage_overrides.block_device_mappings) > 0 ?
      var.worker_config.gpu_config.gpu_storage_overrides.block_device_mappings :
    var.worker_config.worker_storage_overrides.block_device_mappings)

    # AMI selection (use base AMI)
    aws_ami = local.aws_ami

    # Worker role (can be different for GPU workers)
    worker_role_name = coalesce(
      var.iam_config.gpu_worker_role_name,
      var.iam_config.worker_role_name,
      var.iam_config.control_plane_role_name,
      "${local.cluster_name}-gpu-worker-role"
    )
  }

  # GPU-specific settings
  gpu_type       = var.worker_config.gpu_config.gpu_type
  gpu_memory_min = var.worker_config.gpu_config.gpu_memory_min
}

module "gpu_workers" {
  # Only create if GPU workers are configured
  count = local.gpu_config.total_count > 0 ? 1 : 0

  source = "./gpu-workers"

  cluster_name            = local.cluster_name
  log_level               = local.gpu_config.log_level
  k8s_scripts_bucket_name = local.k8s_scripts_bucket_name

  aws_ami                   = local.gpu_config.aws_ami
  use_instance_requirements = local.gpu_config.use_instance_requirements

  subnet_ids         = local.subnet_ids
  security_group_ids = local.security_group_ids

  ssm_join_command_path      = local.ssm_join_command_path
  k8s_user                   = local.k8s_user
  k8s_major_minor_stream     = local.k8s_major_minor_stream
  k8s_package_version_string = local.k8s_package_version_string

  min_size          = local.gpu_config.asg_config.min_size
  max_size          = local.gpu_config.asg_config.max_size
  health_check_type = local.gpu_config.asg_config.health_check_type

  # Apply GPU-specific overrides or use base config
  health_check_grace_period = local.gpu_config.asg_config.health_check_grace_period
  min_healthy_percentage    = local.gpu_config.asg_config.min_healthy_percentage
  instance_warmup           = local.gpu_config.asg_config.instance_warmup

  # Storage configuration - use GPU overrides or base config
  block_device_mappings = local.gpu_config.block_device_mappings

  # Worker role (can be different for GPU workers)
  worker_role_name = local.gpu_config.worker_role_name

  # GPU-specific settings
  gpu_type = local.gpu_type

  # Tags with GPU-specific additions
  additional_tags = merge(
    {
      WorkerType    = "gpu"
      Environment   = local.environment
      Project       = var.core_config.project
      CostTier      = "premium"
      HighCostAlert = "true"
      GPUType       = local.gpu_type
    },
    var.worker_config.additional_tags
  )
}
