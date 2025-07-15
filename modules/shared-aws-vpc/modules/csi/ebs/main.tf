# modules/csi/ebs/main.tf

resource "kubernetes_namespace" "ebs_csi" {
  metadata {
    name = "kube-system"
  }
}

resource "helm_release" "ebs_csi_driver" {
  name       = "aws-ebs-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
  chart      = "aws-ebs-csi-driver"
  namespace  = kubernetes_namespace.ebs_csi.metadata[0].name
  version    = var.helm_chart_version

  values = [
    yamlencode({
      controller = {
        serviceAccount = {
          create = true
          name   = var.service_account_name
        }
      },
      node = {
        serviceAccount = {
          create = true
          name   = var.service_account_name
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.ebs_csi]
}

resource "kubernetes_storage_class" "ebs_sc" {
  metadata {
    name = var.storage_class_name
  }

  provisioner          = "ebs.csi.aws.com"
  reclaim_policy       = "Delete"
  volume_binding_mode  = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type = "gp3"
    fsType = "ext4"
  }
}
