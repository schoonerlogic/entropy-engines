
# 🕰️ clockwork-codex: SSH Config Module

> *"A whisper through the bastion, a portal into the clockwork mind."
> — The Codex Whisperer*

This module is part of **Clockwork Codex**, a system designed for orchestrated knowledge synthesis, enabling Kubernetes clusters to emerge from raw compute and flow data like gears of a great machine.

The `ssh-config` module dynamically builds an SSH configuration to access a private Kubernetes cluster (controllers and worker nodes), securely tunneled through a bastion host.

## ✨ Features

- Supports both **on-demand** and **spot** instances
- Distinguishes between **controller**, **CPU**, and **GPU** worker nodes
- Dynamically renders host blocks from Terraform data
- Bastion-enabled with jump host proxying

## 📦 Inputs

| Variable                   | Description                                      |
|---------------------------|--------------------------------------------------|
| `output_path`             | Path to write the generated SSH config           |
| `template_path`           | Path to `ssh_config.tpl` template                |
| `bastion_hostname`        | Public IP or DNS of the bastion host            |
| `bastion_user`            | SSH user for the bastion                        |
| `ssh_private_key`         | Path to private key used to access all hosts    |
| `controller_nodes`        | On-demand controller nodes (if used)            |
| `controller_spot_instances` | Spot controllers (if enabled)                |
| `use_controller_spot`     | Whether using spot controllers                  |
| `k8s_worker_cpus`         | On-demand CPU workers                           |
| `cpu_spot_instances`      | Spot CPU workers                                |
| `use_cpu_spot`            | Whether using spot CPU workers                  |
| `has_cpu_workers`         | Whether any CPU workers exist                   |
| `k8s_worker_gpus`         | On-demand GPU workers                           |
| `gpu_spot_instances`      | Spot GPU workers                                |
| `use_gpu_spot`            | Whether using spot GPU workers                  |
| `has_gpu_workers`         | Whether any GPU workers exist                   |

## 🧠 Usage

```hcl
module "ssh_config" {
  source           = "./modules/ssh-config"
  output_path      = "${path.module}/graphscope_ssh_config"
  template_path    = "${path.module}/templates/ssh_config.tpl"

  bastion_hostname = module.network.bastion_public_ip
  bastion_user     = var.bastion_user
  ssh_private_key  = var.ssh_private_key_path

  controller_nodes          = local.controller_nodes
  controller_spot_instances = local.controller_spot_instances
  use_controller_spot       = var.use_controller_spot

  k8s_worker_cpus           = local.k8s_worker_cpus
  cpu_spot_instances        = local.cpu_spot_instances
  use_cpu_spot              = var.use_cpu_spot
  has_cpu_workers           = local.has_cpu_workers

  k8s_worker_gpus           = local.k8s_worker_gpus
  gpu_spot_instances        = local.gpu_spot_instances
  use_gpu_spot              = var.use_gpu_spot
  has_gpu_workers           = local.has_gpu_workers
}
```

## 🛠️ Output

Generates a local file (`graphscope_ssh_config`) that lets you:

```bash
ssh controller-0
ssh cpu-worker-1
ssh gpu-worker-0
```

...all routed through the bastion, as designed.

## 🌀 Part of Clockwork Codex

> “What is built from logic becomes architecture. What is bound by pattern becomes thought.”

Use this module with:
- `modules/network`
- `modules/controller`
- `modules/cpu-workers`
- `modules/gpu-workers`
- `modules/graphscope`

---
🧭 **Navigate your cluster. Harness your data. Feed the Codex.**
