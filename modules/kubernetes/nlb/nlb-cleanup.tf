# =================================================================
# NLB CLEANUP ONLY - Does not create, only destroys
# =================================================================

locals {
  aws_region     = var.aws_region
  cluster_name   = var.cluster_name
  nlb_param_name = "/k8s/${local.cluster_name}/nlb-arn"
}

resource "null_resource" "nlb_cleanup" {

  # depends_on = [
  #   module.kubernetes
  #   # Add all resources that use the NLB
  # ]
  #
  triggers = {
    always_run = timestamp()
  }

  # NO creation provisioner - this resource does nothing on apply

  # ONLY cleanup on destroy
  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/scripts/cleanup-nlb-from-ssm.sh"
    environment = {
      CLUSTER_NAME = self.triggers.cluster_name
      AWS_REGION   = self.triggers.aws_region
      NLB_PARAM    = self.triggers.nlb_param_name
    }
  }
}
