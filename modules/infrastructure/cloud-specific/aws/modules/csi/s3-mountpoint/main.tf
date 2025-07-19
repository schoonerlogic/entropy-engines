# modules/csi/s3-mountpoint/main.tf

resource "kubernetes_namespace" "mountpoint" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "s3_csi_driver" {
  name       = "mountpoint-s3-csi-driver"
  repository = "https://awslabs.github.io/mountpoint-s3-csi-driver"
  chart      = "mountpoint-s3-csi-driver"
  namespace  = kubernetes_namespace.mountpoint.metadata[0].name
  version    = var.helm_chart_version

  values = [
    yamlencode({
      driver = {
        region    = var.aws_region
        mountPath = "/mnt/s3"
        logging = {
          level = "info"
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.mountpoint]
}

resource "kubernetes_storage_class" "s3_sc" {
  metadata {
    name = var.storage_class_name
  }

  provisioner = "s3.csi.aws.com"

  parameters = {
    bucketName   = var.bucket_name
    region       = var.aws_region
    mountOptions = ""
  }

  reclaim_policy         = "Retain"
  volume_binding_mode    = "Immediate"
  allow_volume_expansion = false
}
