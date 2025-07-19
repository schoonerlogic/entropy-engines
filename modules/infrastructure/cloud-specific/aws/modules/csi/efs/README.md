# 📦 Clockwork Codex — EFS CSI Module

> *“A thread of memory, ever shared, woven between minds of the machine.”*

This module installs the AWS EFS CSI Driver via Helm and provisions a fully managed **Elastic File System (EFS)** for your Kubernetes workloads.

It is purpose-built for GraphScope deployments that require **persistent, shared, POSIX-compliant storage** across pods and nodes — perfect for intermediate state, logs, streaming data, and cooperative graph computation.

---

## ✨ Features

- Provisions an EFS file system with mount targets in all subnets
- Deploys the EFS CSI driver into your cluster
- Creates a `StorageClass` that enables seamless access to EFS volumes
- Supports volume expansion and parallel consumption

---

## 🔧 Usage

```hcl
module "efs_csi" {
  source              = "./modules/csi/efs"
  aws_region          = var.region
  cluster_name        = var.cluster_name
  subnet_ids          = module.network.private_subnets
  security_group_id   = module.network.security_group_id
  storage_class_name  = "efs-sc"
}
```

Mount in workloads:

```yaml
spec:
  storageClassName: efs-sc
```

---

## 📥 Inputs

| Name                 | Description                               | Default       |
|----------------------|-------------------------------------------|---------------|
| `aws_region`         | AWS region for deployment                 | *(required)*  |
| `cluster_name`       | Cluster name to tag and label EFS         | *(required)*  |
| `subnet_ids`         | Private subnet IDs to mount into          | *(required)*  |
| `security_group_id`  | Security group for EFS mount targets      | *(required)*  |
| `namespace`          | Kubernetes namespace for the CSI driver   | `kube-system` |
| `storage_class_name` | Name of the EFS storage class             | `efs-sc`      |
| `helm_chart_version` | Helm chart version                        | `2.4.5`       |

---

## 📤 Outputs

| Output              | Description                     |
|---------------------|---------------------------------|
| `storage_class_name` | Registered StorageClass         |
| `file_system_id`     | ID of the created EFS instance  |

---

## 🧠 When to Use

- You need **shared, concurrent** file access across pods
- You want persistent state with standard file semantics
- You’re processing logs, checkpoints, or intermediate graph data

> *“Memory shared is memory kept. Storage that endures binds the cluster together.”*

---

🧠 **Clockwork Codex** — persistence, with purpose.
