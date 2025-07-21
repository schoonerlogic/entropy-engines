# modules/gpu-workers/main.tf
# GPU-specific wrapper around worker-base

#===============================================================================
# GPU Workers Implementation
#===============================================================================

module "gpu_worker_base" {
  source = "../worker-base"

  # Core identification
  cluster_name = var.cluster_name
  worker_type  = "gpu"

  # Instance configuration (passed through from parent)
  instance_types            = var.instance_types
  use_instance_requirements = var.use_instance_requirements
  instance_requirements     = var.instance_requirements
  on_demand_count           = var.on_demand_count
  spot_count                = var.spot_count
  ami_id                    = var.ami_id

  # Kubernetes configuration
  k8s_user               = var.k8s_user
  k8s_major_minor_stream = var.k8s_major_minor_stream
  cluster_dns_ip         = var.cluster_dns_ip

  # Networking
  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids
  ssh_key_name       = var.ssh_key_name

  # IAM (might be different role for GPU workers)
  worker_role_name   = var.worker_role_name
  iam_policy_version = var.iam_policy_version

  # S3 bootstrap (GPU workers use gpu-node-init.sh)
  bootstrap_bucket_name = var.bootstrap_bucket_name
  bootstrap_script_name = "gpu-node-init.sh"

  # ASG Configuration (GPU-optimized defaults)
  min_size                  = var.min_size
  max_size                  = var.max_size
  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period
  min_healthy_percentage    = var.min_healthy_percentage
  instance_warmup           = var.instance_warmup
  capacity_timeout          = var.capacity_timeout
  instance_refresh_triggers = var.instance_refresh_triggers

  # Spot configuration (GPU-specific)
  spot_allocation_strategy = var.spot_allocation_strategy
  spot_instance_pools      = var.spot_instance_pools

  # Storage configuration (typically larger for GPU workers)
  block_device_mappings = var.block_device_mappings

  # GPU-specific settings (set reasonable defaults for GPU workers)
  gpu_type       = "nvidia" # GPU workers are typically NVIDIA
  gpu_memory_min = null     # Let instance requirements handle this

  # Tags (add GPU-specific defaults)
  additional_tags = merge(
    {
      WorkerClass     = "gpu-accelerated"
      CostTier        = "premium"
      HighCostAlert   = "true"
      GPUAccelerated  = "true"
      MonitoringLevel = "enhanced"
    },
    var.additional_tags
  )
}

#===============================================================================
# Local Values for GPU Workers
#===============================================================================

locals {
  # GPU-specific information that might be useful
  gpu_worker_info = {
    supports_cuda         = var.gpu_type == "nvidia"
    supports_ml_workloads = true
    requires_gpu_drivers  = true
    typical_workloads     = ["machine-learning", "ai-training", "gpu-compute"]
  }
}
