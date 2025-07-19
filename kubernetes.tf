
# Spot-enabled worker nodes and controllers
module "controllers" {
  source = "./modules/kubernetes/controllers"

  instance_config   = var.instance_config
  kubernetes_config = var.kubernetes_config
  network_config    = var.network_config
  security_config   = var.security_config

  environment       = var.core_config.environment
  cost_optimization = var.cost_optimization

  base_ami_id = data.aws_ami.ubuntu.id
}


module "worker_cpus" {
  source = "./modules/kubernetes/worker-cpus"

  instance_config   = var.instance_config
  kubernetes_config = var.kubernetes_config
  network_config    = var.network_config
  security_config   = var.security_config

  cost_optimization = var.cost_optimization

  base_ami_id = data.aws_ami.ubuntu.id
}

module "worker_gpus" {
  source = "./modules/kubernetes/worker-gpus"

  instance_config   = var.instance_config
  kubernetes_config = var.kubernetes_config
  network_config    = var.network_config
  security_config   = var.security_config

  cost_optimization = var.cost_optimization

  base_ami_id      = data.aws_ami.ubuntu.id
  bootstrap_script = var.bootstrap_script
}

