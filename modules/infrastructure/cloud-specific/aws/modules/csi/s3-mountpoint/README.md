
# 📦 Clockwork Codex — Mountpoint S3 CSI Module

> *"Let the cloud speak as a filesystem, and the code listen as if local."*

This module installs the [Mountpoint for Amazon S3 CSI Driver](https://github.com/awslabs/mountpoint-s3-csi-driver) in your Kubernetes cluster using Helm.

It configures a `StorageClass` backed by an S3 bucket, allowing your workloads to mount object storage as if it were a traditional POSIX filesystem — with the scalability and durability of S3.

---

## ✨ Features

- Deploys S3 CSI driver via Helm
- Creates a reusable `StorageClass`
- Targets a specific S3 bucket and region
- Ready for analytics, logs, checkpoints, and more

---

## 🔧 Usage

```hcl
module "s3_mountpoint_csi" {
  source              = "./modules/csi/s3-mountpoint"
  aws_region          = var.region
  bucket_name         = module.storage.bucket_name
  storage_class_name  = "s3-mountpoint"
}
```

Use it in your pods:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: s3-volume
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: s3-mountpoint
  resources:
    requests:
      storage: 10Gi
```

---

## 📥 Inputs

| Name               | Description                            | Default         |
|--------------------|----------------------------------------|-----------------|
| `aws_region`       | AWS region where the bucket exists     | *(required)*    |
| `bucket_name`      | Name of the S3 bucket to mount         | *(required)*    |
| `storage_class_name` | StorageClass name                   | `s3-mountpoint` |
| `helm_chart_version` | Helm chart version to install        | `0.1.0`         |
| `namespace`        | Kubernetes namespace for deployment    | `kube-system`   |

---

## 🧪 Outputs

| Output              | Description                   |
|---------------------|-------------------------------|
| `storage_class_name` | Name of the created class     |

---

## 🧠 When to Use

Mountpoint for S3 is ideal when:
- You want **POSIX-style** access to object storage
- You want fast **read-heavy** access without block storage
- You need to feed or checkpoint ML/graph jobs from S3

> *“Storage becomes thought when it is both accessible and ephemeral. We mount what we remember.”*

---

🧠 **Clockwork Codex** — where your data lakes meet the gears of reason.
