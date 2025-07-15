
Host ${project}-bastion
  HostName "${bastion_host}"
  User ${bastion_user}
  IdentityFile ${ssh_private_key_path}
  ForwardAgent yes
  IdentitiesOnly yes
  StrictHostKeyChecking no


