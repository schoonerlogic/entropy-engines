# root - kubernetes.tf


# resource "aws_s3_bucket" "bootstrap_bucket" {
#   # The bucket name must be globally unique across all of AWS.
#   # You should replace "my-unique-bucket-name-12345" with a name
#   # that you choose.
#   bucket        = "${var.network_config.bootstrap_bucket_name}-${random_id.bucket_suffix.hex}"
#   force_destroy = true
#   # Tags are key-value pairs that you can attach to AWS resources.
#   # They are useful for organizing and managing your resources.
#   tags = {
#     Name        = "${var.network_config.bootstrap_bucket_name}-${random_id.bucket_suffix.hex}"
#     Environment = "Dev"
#   }
# }

# resource "random_id" "bucket_suffix" {
#   byte_length = 4
# }

# Controllers Module - No Provisioners, Self-Bootstrapping
module "controllers" {
  source = "./modules/kubernetes/controllers"

  # Core configuration
  cluster_name = var.kubernetes_config.cluster_name != null ? var.kubernetes_config.cluster_name : var.core_config.project
  environment  = var.core_config.environment

  # Instance configuration
  on_demand_count = var.k8s_control_plane_config.on_demand_count
  spot_count      = var.k8s_control_plane_config.spot_count
  instance_types  = [var.k8s_control_plane_config.instance_type]

  base_aws_ami = data.aws_ami.ubuntu.id

  # Kubernetes configuration
  k8s_user               = var.kubernetes_config.k8s_user
  k8s_major_minor_stream = var.kubernetes_config.k8s_major_minor_stream
  k8s_full_patch_version = var.kubernetes_config.k8s_full_patch_version
  k8s_apt_package_suffix = var.kubernetes_config.k8s_apt_package_suffix
  pod_cidr_block         = module.aws_infrastructure.pod_cidr_block
  service_cidr_block     = module.aws_infrastructure.service_cidr_block

  # Networking
  subnet_ids         = module.aws_infrastructure.private_subnet_ids
  security_group_ids = [module.aws_infrastructure.control_plane_security_group_id]

  # IAM
  control_plane_role_name = (var.iam_config.control_plane_role_name != null ?
  var.iam_config.control_plane_role_name : "${var.core_config.project}-control-plane-role")

  # S3
  bootstrap_bucket_name = module.aws_infrastructure.bootstrap_bucket_name
  # bootstrap_bucket_dependency = aws_s3_bucket.bootstrap_bucket.bucket

  # SSH (still needed for troubleshooting, but not used by bootstrap process)
  ssh_key_name         = var.security_config.ssh_key_name
  ssh_public_key_path  = var.security_config.ssh_public_key_path
  ssh_private_key_path = var.security_config.ssh_private_key_path

  # Storage configuration
  block_device_mappings = coalesce(
    var.k8s_control_plane_config.block_device_mappings,
    var.instance_config.default_block_device_mappings
  )

  # ASG configuration (control plane needs different settings)
  health_check_grace_period = 600   # Longer for control plane bootstrap
  min_healthy_percentage    = 50    # Standard for control plane
  capacity_timeout          = "20m" # Longer timeout for control plane

  # Spot configuration (control plane typically uses less spot)
  spot_allocation_strategy = "capacity-optimized"
  spot_instance_pools      = 2

  # Tags
  additional_tags = {
    Environment  = var.core_config.environment
    Project      = var.core_config.project
    CostCenter   = "infrastructure"
    Criticality  = "high"
    BackupPolicy = "daily"
  }

  depends_on = [data.aws_ami.ubuntu]
}

locals {
  # Derived values
  cluster_name = var.kubernetes_config.cluster_name != null ? var.kubernetes_config.cluster_name : var.core_config.project

  # CPU Worker Configuration (built from base worker_config + CPU-specific defaults)
  cpu_worker_config = {
    # Core identification
    worker_type  = "cpu"
    cluster_name = local.cluster_name

    # Instance configuration - use base or CPU-specific defaults
    instance_types = length(var.worker_config.instance_types) > 0 ? var.worker_config.instance_types : [
      "c6i.large", "c6i.xlarge", "c5.large", "c5.xlarge", "m6i.large", "m6i.xlarge"
    ]

    use_instance_requirements = var.worker_config.use_instance_requirements

    # Instance requirements with CPU-specific defaults
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
    min_size                  = var.worker_config.asg_config.min_size
    max_size                  = var.worker_config.asg_config.max_size
    health_check_type         = var.worker_config.asg_config.health_check_type
    health_check_grace_period = coalesce(var.worker_config.asg_config.health_check_grace_period, 300) # CPU workers boot faster
    min_healthy_percentage    = coalesce(var.worker_config.asg_config.min_healthy_percentage, 50)     # Standard for CPU
    instance_warmup           = coalesce(var.worker_config.asg_config.instance_warmup, 180)           # Faster warmup
    capacity_timeout          = var.worker_config.asg_config.capacity_timeout
    instance_refresh_triggers = var.worker_config.asg_config.instance_refresh_triggers

    # Spot configuration with CPU-optimized defaults
    spot_allocation_strategy = coalesce(var.worker_config.spot_config.spot_allocation_strategy, "capacity-optimized")
    spot_instance_pools      = coalesce(var.worker_config.spot_config.spot_instance_pools, 4) # More pools for better availability

    # Storage configuration - use base defaults (CPU workers are lightweight)
    block_device_mappings = coalesce(
      var.worker_config.worker_storage_overrides.block_device_mappings,
      var.instance_config.default_block_device_mappings
    )

    # AMI selection
    base_aws_ami = data.aws_ami.ubuntu.id

    # Worker role
    worker_role_name = coalesce(
      var.iam_config.worker_role_name,
      var.iam_config.control_plane_role_name,
      "${local.cluster_name}-worker-role"
    )

    # Tags
    additional_tags = merge(
      {
        WorkerType  = "cpu"
        Environment = var.core_config.environment
        Project     = var.core_config.project
        CostTier    = "standard"
      },
      var.worker_config.additional_tags
    )
  }

  # GPU Worker Configuration (built from base worker_config + GPU-specific defaults/overrides)
  gpu_worker_config = {
    # Core identification
    worker_type  = "gpu"
    cluster_name = local.cluster_name

    # Instance configuration - use base or GPU-specific defaults
    instance_types = length(var.worker_config.instance_types) > 0 ? var.worker_config.instance_types : [
      "g5.xlarge", "g5.2xlarge", "g5.4xlarge", "g4dn.xlarge", "g4dn.2xlarge", "g4dn.4xlarge"
    ]

    use_instance_requirements = var.worker_config.use_instance_requirements

    # Instance requirements with GPU-specific defaults
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
    var.worker_config.storage_config.block_device_mappings)

    # AMI selection (use GPU AMI if provided, otherwise base AMI)
    base_aws_ami = data.aws_ami.ubuntu.id

    # Worker role (can be different for GPU workers)
    worker_role_name = coalesce(
      var.iam_config.gpu_worker_role_name,
      var.iam_config.worker_role_name,
      var.iam_config.control_plane_role_name,
      "${local.cluster_name}-gpu-worker-role"
    )

    # GPU-specific settings
    gpu_type       = var.worker_config.gpu_config.gpu_type
    gpu_memory_min = var.worker_config.gpu_config.gpu_memory_min

    # Tags with GPU-specific additions
    additional_tags = merge(
      {
        WorkerType    = "gpu"
        Environment   = var.core_config.environment
        Project       = var.core_config.project
        CostTier      = "premium"
        HighCostAlert = "true"
        GPUType       = var.worker_config.gpu_config.gpu_type
      },
      var.worker_config.additional_tags
    )
  }
}

# CPU Workers Module
module "cpu_workers" {
  source = "./modules/kubernetes/cpu-workers"

  count = local.cpu_worker_config.total_count > 0 ? 1 : 0

  # Pass the clean, merged configuration
  cluster_name              = local.cpu_worker_config.cluster_name
  worker_type               = local.cpu_worker_config.worker_type
  instance_types            = local.cpu_worker_config.instance_types
  use_instance_requirements = local.cpu_worker_config.use_instance_requirements
  instance_requirements     = local.cpu_worker_config.instance_requirements
  on_demand_count           = local.cpu_worker_config.on_demand_count
  spot_count                = local.cpu_worker_config.spot_count
  base_aws_ami              = data.aws_ami.ubuntu.id

  # Kubernetes config (from original variables)
  k8s_user               = var.kubernetes_config.k8s_user
  k8s_major_minor_stream = var.kubernetes_config.k8s_major_minor_stream
  cluster_dns_ip         = var.network_config.kubernetes_cidrs.pod_cidr

  # Networking
  subnet_ids         = module.aws_infrastructure.private_subnet_ids
  security_group_ids = [module.aws_infrastructure.worker_nodes_security_group_id]

  # IAM
  worker_role_name   = local.cpu_worker_config.worker_role_name
  iam_policy_version = var.network_config.iam_policy_version

  # S3
  bootstrap_bucket_name = var.network_config.bootstrap_bucket_name
  # bootstrap_bucket_dependency = aws_s3_bucket.bootstrap_bucket.bucket
  # SSH
  ssh_key_name = var.security_config.ssh_key_name

  # ASG Configuration
  min_size                  = local.cpu_worker_config.min_size
  max_size                  = local.cpu_worker_config.max_size
  health_check_type         = local.cpu_worker_config.health_check_type
  health_check_grace_period = local.cpu_worker_config.health_check_grace_period
  min_healthy_percentage    = local.cpu_worker_config.min_healthy_percentage
  instance_warmup           = local.cpu_worker_config.instance_warmup
  capacity_timeout          = local.cpu_worker_config.capacity_timeout
  instance_refresh_triggers = local.cpu_worker_config.instance_refresh_triggers

  # Spot configuration
  spot_allocation_strategy = local.cpu_worker_config.spot_allocation_strategy
  spot_instance_pools      = local.cpu_worker_config.spot_instance_pools

  # Storage
  block_device_mappings = local.cpu_worker_config.block_device_mappings

  # Tags
  additional_tags = local.cpu_worker_config.additional_tags
}

# GPU Workers Module
module "gpu_workers" {
  source = "./modules/kubernetes/gpu-workers"

  count = var.kubernetes_config.enable_gpu_nodes && local.gpu_worker_config.total_count > 0 ? 1 : 0

  # Pass the clean, merged configuration
  cluster_name              = local.gpu_worker_config.cluster_name
  worker_type               = local.gpu_worker_config.worker_type
  instance_types            = local.gpu_worker_config.instance_types
  use_instance_requirements = local.gpu_worker_config.use_instance_requirements
  instance_requirements     = local.gpu_worker_config.instance_requirements
  on_demand_count           = local.gpu_worker_config.on_demand_count
  spot_count                = local.gpu_worker_config.spot_count
  base_gpu_ami              = data.aws_ami.ubuntu.id
  # Kubernetes config
  k8s_user               = var.kubernetes_config.k8s_user
  k8s_major_minor_stream = var.kubernetes_config.k8s_major_minor_stream
  cluster_dns_ip         = var.network_config.cluster_dns_ip

  # Networking
  subnet_ids         = module.aws_infrastructure.private_subnet_ids
  security_group_ids = [module.aws_infrastructure.worker_nodes_security_group_id]

  # IAM
  worker_role_name   = local.gpu_worker_config.worker_role_name
  iam_policy_version = var.network_config.iam_policy_version

  # S3
  bootstrap_bucket_name = var.network_config.bootstrap_bucket_name
  # bootstrap_bucket_dependency = aws_s3_bucket.bootstrap_bucket.bucket

  # SSH
  ssh_key_name = var.security_config.ssh_key_name

  # ASG Configuration
  min_size                  = local.gpu_worker_config.min_size
  max_size                  = local.gpu_worker_config.max_size
  health_check_type         = local.gpu_worker_config.health_check_type
  health_check_grace_period = local.gpu_worker_config.health_check_grace_period
  min_healthy_percentage    = local.gpu_worker_config.min_healthy_percentage
  instance_warmup           = local.gpu_worker_config.instance_warmup
  capacity_timeout          = local.gpu_worker_config.capacity_timeout
  instance_refresh_triggers = local.gpu_worker_config.instance_refresh_triggers

  # Spot configuration
  spot_allocation_strategy = local.gpu_worker_config.spot_allocation_strategy
  spot_instance_pools      = local.gpu_worker_config.spot_instance_pools

  # Storage
  block_device_mappings = local.gpu_worker_config.block_device_mappings

  # Tags
  additional_tags = local.gpu_worker_config.additional_tags
}

module "ssh_config" {
  source = "./modules/ssh-config"

  cluster_name         = local.cluster_name
  bastion_host         = module.aws_infrastructure.bastion_public_ip
  bastion_user         = var.security_config.bastion_user
  k8s_user             = var.kubernetes_config.k8s_user
  ssh_private_key_path = var.security_config.ssh_private_key_path

  controller_private_ips = module.controllers.private_ips
  worker_gpu_private_ips = length(module.gpu_workers) > 0 ? module.gpu_workers[0].private_ips : []
  worker_cpu_private_ips = length(module.cpu_workers) > 0 ? module.cpu_workers[0].private_ips : []
}

