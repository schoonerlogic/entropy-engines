
# modules/csi/efs/main.tf

resource "kubernetes_namespace" "efs_csi" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "efs_csi_driver" {
  name       = "aws-efs-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-efs-csi-driver"
  chart      = "aws-efs-csi-driver"
  namespace  = kubernetes_namespace.efs_csi.metadata[0].name
  version    = var.helm_chart_version

  values = [
    yamlencode({
      controller = {
        region = var.aws_region
      },
      node = {
        region = var.aws_region
      }
    })
  ]

  depends_on = [kubernetes_namespace.efs_csi]
}

resource "aws_efs_file_system" "graphscope_efs" {
  creation_token = "${var.cluster_name}-efs"

  tags = {
    Name = "${var.cluster_name}-efs"
  }
}

resource "aws_efs_mount_target" "mount_targets" {
  count           = length(var.subnet_ids)
  file_system_id  = aws_efs_file_system.graphscope_efs.id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = [var.security_group_id]
}

resource "kubernetes_storage_class" "efs_sc" {
  metadata {
    name = var.storage_class_name
  }

  provisioner = "efs.csi.aws.com"

  parameters = {
    provisioningMode = "efs-ap"
    fileSystemId     = aws_efs_file_system.graphscope_efs.id
    directoryPerms   = "700"
  }

  reclaim_policy         = "Retain"
  volume_binding_mode    = "Immediate"
  allow_volume_expansion = true
}
