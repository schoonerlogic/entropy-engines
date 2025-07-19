#!/bin/bash

set -euxo pipefail 

echo "Bootstrap script started at $(date) in $(pwd)" # Add timestamp/context

LOG_FILE="/var/log/bootstrap.log"
exec > >(tee -a $${LOG_FILE}) 2>&1 # Redirect stdout/stderr to log file and console


# --- Configuration Variables (Passed from Terraform Templatefile) ---
# Ensure these are provided by your templatefile data source's 'vars' map
TARGET_USER="${k8s_user}"
K8S_REPO_STREAM="${k8s_repo_stream_for_apt}" # e.g., 1.33 (used for repo URL)
K8S_PKG_VERSION_STRING="${k8s_package_version_for_install}" # e.g., 1.33.1-00 (used for apt install)



# --- Fetch Instance Private IP ---
echo "Fetching instance private IP from metadata..."
INSTANCE_PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
if [ -z "$INSTANCE_PRIVATE_IP" ]; then
    echo "FATAL: Could not determine instance private IP from metadata service."
    exit 1
fi
echo "Instance private IP: $${INSTANCE_PRIVATE_IP}"
# --- End Fetch Instance Private IP ---


echo "Setting up user: $${TARGET_USER}"

# --- User Setup ---
# Create user if they don't exist
if ! id "$${TARGET_USER}" &>/dev/null; then
    echo "Creating user $${TARGET_USER}..."
    useradd -m -s /bin/bash "$${TARGET_USER}"
    passwd -d "$${TARGET_USER}" # Ensure password login is disabled if desired
else
    echo "User $${TARGET_USER} already exists."
fi

# Configure passwordless sudo
echo "$${TARGET_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$${TARGET_USER}" # Use > instead of | sudo tee
chmod 440 "/etc/sudoers.d/$${TARGET_USER}"

# Set up SSH key authentication from EC2 metadata
SSH_PUBLIC_KEY=$(curl -fsSL http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key || echo "Failed to fetch SSH key from metadata")
if [[ -n "$SSH_PUBLIC_KEY" && "$SSH_PUBLIC_KEY" != "Failed to fetch"* ]]; then
    USER_SSH_DIR="/home/$${TARGET_USER}/.ssh"
    mkdir -p "$${USER_SSH_DIR}"
    echo "$${SSH_PUBLIC_KEY}" > "$${USER_SSH_DIR}/authorized_keys"
    chmod 700 "$${USER_SSH_DIR}"
    chmod 600 "$${USER_SSH_DIR}/authorized_keys"
    chown -R "$${TARGET_USER}:$${TARGET_USER}" "$${USER_SSH_DIR}" # Assuming group name matches username
    echo "SSH key configured for $${TARGET_USER}"
else
    echo "Warning: Could not retrieve SSH public key for $${TARGET_USER}."
    # Decide if this is a fatal error? If SSH is essential, add 'exit 1'
fi

echo "Starting Kubernetes setup on EC2..."

# Disable swap
swapoff -a
sed -i.bak '/ swap / s/^/#/' /etc/fstab # Added .bak for safety

# Enable kernel modules
modprobe overlay
modprobe br_netfilter
echo -e "overlay\nbr_netfilter" > /etc/modules-load.d/k8s.conf # Use > instead of tee
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/k8s.conf

# Configure sysctl params
echo "net.bridge.bridge-nf-call-iptables = 1" > /etc/sysctl.d/k8s.conf # Added bridge setting often needed
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.d/k8s.conf # Use >> to append
sysctl --system # Reload sysctl settings


# Install dependencies
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gpg awscli jq

# Install Kubernetes (using specific version passed from Terraform)
K8S_KEYRING_DIR="/etc/apt/keyrings"
K8S_KEYRING_FILE="$${K8S_KEYRING_DIR}/kubernetes-apt-keyring.gpg"
K8S_REPO_FILE="/etc/apt/sources.list.d/kubernetes.list"

echo "Setting up Kubernetes APT repository for stream v$${K8S_REPO_STREAM} ...."
sudo mkdir -p "$${K8S_KEYRING_DIR}"
sudo curl -fsSL "https://pkgs.k8s.io/core:/stable:/v$${K8S_REPO_STREAM}/deb/Release.key" | sudo gpg --dearmor -o "$${K8S_KEYRING_FILE}" || { echo "Failed to download k8s gpg key for stream v$${K8S_REPO_STREAM}"; exit 1; }
echo "deb [signed-by=$${K8S_KEYRING_FILE}] https://pkgs.k8s.io/core:/stable:/v$${K8S_REPO_STREAM}/deb/ /" | sudo tee "$${K8S_REPO_FILE}" > /dev/null || { echo "Failed to write k8s repo file"; exit 1; }

sudo apt-get update

echo "Installing Kubernetes packages: kubelet=$${K8S_PKG_VERSION_STRING}, kubeadm=$${K8S_PKG_VERSION_STRING}, kubectl=$${K8S_PKG_VERSION_STRING}"
sudo apt-get install -y \
  kubelet="$${K8S_PKG_VERSION_STRING}" \
  kubeadm="$${K8S_PKG_VERSION_STRING}" \
  kubectl="$${K8S_PKG_VERSION_STRING}" || {
    echo "Failed to install specific Kubernetes package versions. Trying to find them..."
    echo "Available kubeadm versions:"
    apt-cache madison kubeadm
    exit 1
  }

apt-mark hold kubelet kubeadm kubectl

# Install and configure containerd
CONTAINERD_KEYRING_DIR="/usr/share/keyrings"
CONTAINERD_KEYRING_FILE="$${CONTAINERD_KEYRING_DIR}/docker-archive-keyring.gpg"
CONTAINERD_REPO_FILE="/etc/apt/sources.list.d/docker.list"

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o "$${CONTAINERD_KEYRING_FILE}" || { echo "Failed to download docker/containerd gpg key"; exit 1; }
echo "deb [arch=$(dpkg --print-architecture) signed-by=$${CONTAINERD_KEYRING_FILE}] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > "$${CONTAINERD_REPO_FILE}" || { echo "Failed to write containerd repo file"; exit 1; }

apt-get update
apt-get install -y containerd.io


echo "Configuring containerd for Kubernetes..."

# Ensure the config directory exists
sudo mkdir -p /etc/containerd

# Generate default config and save it
echo "Generating default containerd config -> /etc/containerd/config.toml"
sudo bash -c 'containerd config default > /etc/containerd/config.toml'

# 1. Comment out the 'disabled_plugins = ["cri"]' line using sed
echo "Ensuring CRI plugin is NOT disabled in containerd config..."
# This sed command finds the exact line and puts a '#' at the beginning
sudo sed -i 's/^disabled_plugins = \["cri"\]/#disabled_plugins = ["cri"]/' /etc/containerd/config.toml

# 2. Modify the config to enable SystemdCgroup (keep this from before)
echo "Enabling SystemdCgroup in containerd config..."
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Restart containerd to apply changes
echo "Restarting containerd service..."
sudo systemctl restart containerd

# Ensure containerd service is enabled on boot
echo "Enabling containerd service..."
sudo systemctl enable containerd




# Optional: Brief wait/check for socket
echo "Waiting briefly for containerd socket..."
sleep 5
if [ ! -S /var/run/containerd/containerd.sock ]; then
  echo "WARNING: containerd socket not found after restart!"
fi

echo "Containerd configured and restarted."
# --- End containerd configuration section ---

echo "-----------------------------------------------------"
echo "Kubernetes control plane setup completed successfully!"
echo "-----------------------------------------------------"
