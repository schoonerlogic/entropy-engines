# SSH Config for ${cluster_name} Cluster
# Generated automatically by Terraform

Host ${cluster_name}-bastion
  HostName ${bastion_host}
  User ${bastion_user}
  IdentityFile ${ssh_private_key_path}
  ForwardAgent yes
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

%{ if has_controllers ~}
%{ for node in controllers ~}

Host ${cluster_name}-controller-${node.index}
  HostName ${node.private_ip}
  User ${k8s_user}
  IdentityFile ${ssh_private_key_path}
  ProxyJump ${cluster_name}-bastion
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

%{ endfor ~}
%{ endif ~}

%{ if has_worker_cpus ~}
%{ for node in worker_cpus ~}

Host ${cluster_name}-cpu-worker-${node.index}
  HostName ${node.private_ip}
  User ${k8s_user}
  IdentityFile ${ssh_private_key_path}
  ProxyJump ${cluster_name}-bastion
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

%{ endfor ~}
%{ endif ~}

%{ if has_worker_gpus ~}
%{ for node in worker_gpus ~}

Host ${cluster_name}-gpu-worker-${node.index}
  HostName ${node.private_ip}
  User ${k8s_user}
  IdentityFile ${ssh_private_key_path}
  ProxyJump ${cluster_name}-bastion
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

%{ endfor ~}
%{ endif ~}

%{ if has_nats_servers ~}
%{ for node in nats_servers ~}

Host ${cluster_name}-nats-${node.index}
  HostName ${node.private_ip}
  User ${k8s_user}
  IdentityFile ${ssh_private_key_path}
  ProxyJump ${cluster_name}-bastion
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

%{ endfor ~}
%{ endif ~}
