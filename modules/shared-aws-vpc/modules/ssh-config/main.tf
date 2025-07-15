# modules/ssh-config/main.tf

resource "local_file" "ssh_config" {
  filename = "${path.module}/../../ssh_config"
  content = templatefile("${path.module}/templates/ssh_config.tpl", {
    project              = var.project,
    bastion_host         = var.bastion_host.public_ip,
    bastion_user         = var.bastion_user,
    ssh_private_key_path = var.ssh_private_key_path,
  })
}

