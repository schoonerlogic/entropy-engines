
resource "null_resource" "deploy_graphscope" {
  provisioner "file" {
    source      = "${path.module}/scripts/deploy-graphscope.sh"
    destination = "/home/graphscope/deploy-graphscope.sh"

    connection {
      type                 = "ssh"
      user                 = var.user
      host                 = var.controller_private_ip
      private_key          = file(var.ssh_private_key_path)
      bastion_host         = var.bastion_public_ip
      bastion_user         = var.bastion_user
      bastion_private_key  = file(var.ssh_private_key_path)
    }
  }

  provisioner "file" {
    source      = "${path.module}/scripts/helm-deployment.yaml"
    destination = "/home/graphscope/helm-deployment.yaml"

    connection {
      type                 = "ssh"
      user                 = var.user
      host                 = var.controller_private_ip
      private_key          = file(var.ssh_private_key_path)
      bastion_host         = var.bastion_public_ip
      bastion_user         = var.bastion_user
      bastion_private_key  = file(var.ssh_private_key_path)
    }
  }

  provisioner "remote-exec" {
    connection {
      type                 = "ssh"
      user                 = var.user
      host                 = var.controller_private_ip
      private_key          = file(var.ssh_private_key_path)
      bastion_public_ip    = var.bastion_public_ip
      bastion_user         = var.bastion_user
      bastion_private_key  = file(var.ssh_private_key_path)
    }

    inline = [
      "chmod +x /home/graphscope/deploy-graphscope.sh",
      "sudo bash /home/graphscope/deploy-graphscope.sh"
    ]
  }

  triggers = {
    always_run = timestamp()
  }
}
