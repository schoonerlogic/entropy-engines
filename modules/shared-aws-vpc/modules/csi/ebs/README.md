# 📦 Clockwork Codex — EBS CSI Module

> *“From block to thought, provisioned by need, vanished on release — such is ephemeral insight.”*

This module installs the AWS EBS CSI Driver into your Kubernetes cluster using Helm and creates a `StorageClass` suitable for GraphScope workloads.

It enables **dynamic block volume provisioning**, high IOPS throughput, and secure integration with AWS IAM and EBS, making it ideal for parallel computation, pod-local data, and temporary state persistence.

---

## ✨ Features

- Installs AWS EBS CSI via Helm in `kube-system`
- Creates a `StorageClass` with `WaitForFirstConsumer` semantics
- Supports expansion, deletion, and per-pod provisioning
- Configurable service account and storage class name

---

## 🔧 Usage

```hcl
module "ebs_csi" {
  source               = "./modules/csi/ebs"
  storage_class_name   = "gp3-ebs"
  service_account_name = "ebs-csi-controller-sa"
}
```

Use in workloads:

```yaml
spec:
  storageClassName: gp3-ebs
```

---

## 📥 Inputs

| Name                  | Description                           | Default                  |
|-----------------------|---------------------------------------|--------------------------|
| `helm_chart_version`  | Helm chart version                    | `2.30.0`                 |
| `storage_class_name`  | Name of the EBS StorageClass          | `ebs-sc`                 |
| `service_account_name`| Name for the controller's service account | `ebs-csi-controller-sa` |

---

## 📤 Outputs

| Output               | Description                   |
|----------------------|-------------------------------|
| `storage_class_name` | Created EBS StorageClass name |

---

## 🧠 When to Use

- Ephemeral per-pod or job-specific block storage
- High-performance reads and writes with `gp3`
- Workloads where isolation and teardown are critical (e.g., analytics jobs, scratch space)

> *“From insight born in IOPS, to discard at pod’s end — a fleeting brilliance mapped to a block.”*

---

🧠 **Clockwork Codex** — orchestration through orchestration.
