
Host ${cluster_name}-bastion
  HostName "${bastion_host}"
  User ${bastion_user}
  IdentityFile ${ssh_private_key_path}
  ForwardAgent yes
  IdentitiesOnly yes
  StrictHostKeyChecking no
 StrictHostKeyChecking no

%{ if has_controllers }
%{ for node in controllers ~}

Host controller-${node.index}
  HostName ${node.private_ip}
  User ${k8s_user}
  ProxyJump bastion
  IdentityFile ${ssh_key_name}
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

%{ endfor ~}
%{ endif }

%{ if has_worker_gpus }
%{ for node in worker_gpus ~}

Host gpu-worker-${node.index}
  HostName ${node.private_ip}
  User ${k8s_user}
  ProxyJump bastion
  IdentityFile ${ssh_key_name}
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

%{ endfor ~}
%{ endif }

%{ if has_worker_cpus }
%{ for node in worker_cpus ~}

Host cpu-worker-${node.index}
  HostName ${node.private_ip}
  User ${k8s_user}
  ProxyJump bastion
  IdentityFile ${ssh_key_name}
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

%{ endfor ~}
%{ endif }
