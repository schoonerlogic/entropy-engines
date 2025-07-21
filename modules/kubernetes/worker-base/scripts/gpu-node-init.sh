#!/bin/bash
set -euo pipefail # Strict mode

# --- Logging Setup ---
LOG_FILE="/var/log/worker-node-bootstrap.log" # Specific name for this script's log
touch "${LOG_FILE}"
chmod 644 "${LOG_FILE}"
exec > >(tee -a "${LOG_FILE}") 2>&1 # Redirect stdout and stderr to log file and console

# --- Color Codes and Logging Functions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
error() { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; exit 1; }

log "Worker Node User Data Script (for unbaked AMI now) started."

# --- Configuration Variables (Passed as command-line arguments) ---

# Check if the required number of arguments are provided
if [ "$#" -lt 4 ]; then
    error "Usage: $0 <target_user> <k8s_repo_stream> <k8s_package_version_string> <ssm_join_command_path>"
fi

TARGET_USER="$1"
K8S_REPO_STREAM="$2"                 # e.g., 1.33 (used for repo URL)
K8S_PKG_VERSION_STRING="$3"          # e.g., 1.33.1-00 (used for apt install)
SSM_JOIN_COMMAND_PATH="$4"           # e.g., /mycluster/worker-join-command

# --- Example: Output the received arguments (for verification) ---
log "Received TARGET_USER: ${TARGET_USER}"
log "Received K8S_REPO_STREAM: ${K8S_REPO_STREAM}"
log "Received K8S_PKG_VERSION_STRING: ${K8S_PKG_VERSION_STRING}"
log "Received SSM_JOIN_COMMAND_PATH: ${SSM_JOIN_COMMAND_PATH}"

# --- Fetch Instance Private IP ---
log "Fetching instance private IP from metadata..."
INSTANCE_PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
if [ -z "${INSTANCE_PRIVATE_IP}" ]; then
    error "FATAL: Could not determine instance private IP from metadata service."
fi
log "Instance private IP: ${INSTANCE_PRIVATE_IP}"
# --- End Fetch Instance Private IP ---


log "Setting up user: ${TARGET_USER}"

# --- User Setup ---
# Create user if they don't exist
if ! id "${TARGET_USER}" &>/dev/null; then
    log "Creating user ${TARGET_USER}..."
    sudo useradd -m -s /bin/bash "${TARGET_USER}"
    sudo passwd -d "${TARGET_USER}" # Ensure password login is disabled if desired
else
    log "User ${TARGET_USER} already exists."
fi

# Configure passwordless sudo
echo "${TARGET_USER} ALL=(ALL) NOPASSWD:ALL" | sudo tee "/etc/sudoers.d/${TARGET_USER}" > /dev/null
sudo chmod 440 "/etc/sudoers.d/${TARGET_USER}"

# Set up SSH key authentication from EC2 metadata
SSH_PUBLIC_KEY=$(curl -fsSL http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key || echo "Failed to fetch SSH key from metadata")
if [[ -n "${SSH_PUBLIC_KEY}" && "${SSH_PUBLIC_KEY}" != "Failed to fetch"* ]]; then
    USER_SSH_DIR="/home/${TARGET_USER}/.ssh"
    sudo mkdir -p "${USER_SSH_DIR}"
    echo "${SSH_PUBLIC_KEY}" | sudo tee "${USER_SSH_DIR}/authorized_keys" > /dev/null
    sudo chmod 700 "${USER_SSH_DIR}"
    sudo chmod 600 "${USER_SSH_DIR}/authorized_keys"
    sudo chown -R "${TARGET_USER}:${TARGET_USER}" "${USER_SSH_DIR}" # Assuming group name matches username
    log "SSH key configured for ${TARGET_USER}"
else
    warn "Could not retrieve SSH public key for ${TARGET_USER}. If SSH access for this user is via EC2 keypair, this might be okay."
fi

log "Starting Kubernetes setup on EC2..."

# Disable swap
log "Disabling swap..."
sudo swapoff -a
sudo sed -i.bak '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab # Comment out swap entries

# Enable kernel modules
log "Enabling kernel modules: overlay, br_netfilter"
sudo modprobe overlay
sudo modprobe br_netfilter
echo -e "overlay\nbr_netfilter" | sudo tee /etc/modules-load.d/k8s.conf > /dev/null

# Configure sysctl params
log "Configuring sysctl for Kubernetes..."
{
  echo "net.bridge.bridge-nf-call-iptables = 1"
  echo "net.ipv4.ip_forward = 1"
} | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf > /dev/null # Use a K8s specific conf file name
sudo sysctl --system # Reload sysctl settings


# Install dependencies
log "Installing dependencies: apt-transport-https, ca-certificates, curl, gpg, awscli, jq"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg awscli jq

# Install Kubernetes (using specific version passed from Terraform)
K8S_KEYRING_DIR="/etc/apt/keyrings"
K8S_KEYRING_FILE="${K8S_KEYRING_DIR}/kubernetes-apt-keyring.gpg"
K8S_REPO_FILE="/etc/apt/sources.list.d/kubernetes.list"

log "Setting up Kubernetes APT repository for stream v${K8S_REPO_STREAM} ...."
sudo mkdir -p "${K8S_KEYRING_DIR}"
TEMP_K8S_GPG_KEY_DOWNLOAD="/tmp/k8s-gpg-key.asc"
log "Downloading Kubernetes GPG key to ${TEMP_K8S_GPG_KEY_DOWNLOAD}..."
if ! curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_REPO_STREAM}/deb/Release.key" -o "${TEMP_K8S_GPG_KEY_DOWNLOAD}"; then
    error "Failed to download Kubernetes GPG key using curl for stream v${K8S_REPO_STREAM}."
fi
log "Dearmoring Kubernetes GPG key from ${TEMP_K8S_GPG_KEY_DOWNLOAD} to ${K8S_KEYRING_FILE}..."
if ! sudo gpg --dearmor --yes --batch -o "${K8S_KEYRING_FILE}" < "${TEMP_K8S_GPG_KEY_DOWNLOAD}"; then
    sudo rm -f "${TEMP_K8S_GPG_KEY_DOWNLOAD}"
    error "Failed to dearmor Kubernetes GPG key for stream v${K8S_REPO_STREAM}."
fi
sudo rm -f "${TEMP_K8S_GPG_KEY_DOWNLOAD}"
log "Kubernetes GPG key successfully processed."

echo "deb [signed-by=${K8S_KEYRING_FILE}] https://pkgs.k8s.io/core:/stable:/v${K8S_REPO_STREAM}/deb/ /" | sudo tee "${K8S_REPO_FILE}" > /dev/null || error "Failed to write k8s repo file"

sudo apt-get update

log "Installing Kubernetes packages: kubelet=${K8S_PKG_VERSION_STRING}, kubeadm=${K8S_PKG_VERSION_STRING}, kubectl=${K8S_PKG_VERSION_STRING}"
sudo apt-get install -y \
  kubelet="${K8S_PKG_VERSION_STRING}" \
  kubeadm="${K8S_PKG_VERSION_STRING}" \
  kubectl="${K8S_PKG_VERSION_STRING}" || {
    warn "Failed to install specific Kubernetes package versions. Trying to find them..."
    warn "Available kubeadm versions:"
    apt-cache madison kubeadm
    error "Exiting due to Kubernetes package installation failure."
  }

sudo apt-mark hold kubelet kubeadm kubectl
log "Kubernetes packages installed and held."

# Install and configure containerd
log "Installing and configuring containerd..."
CONTAINERD_KEYRING_DIR="/usr/share/keyrings" # Standard for newer systems
CONTAINERD_KEYRING_FILE="${CONTAINERD_KEYRING_DIR}/docker-archive-keyring.gpg"
CONTAINERD_REPO_FILE="/etc/apt/sources.list.d/docker.list"
TEMP_DOCKER_GPG_KEY_DOWNLOAD="/tmp/docker-gpg-key.asc" # Temporary file for the downloaded key

sudo mkdir -p "${CONTAINERD_KEYRING_DIR}"

log "Downloading Docker/containerd GPG key to ${TEMP_DOCKER_GPG_KEY_DOWNLOAD}..."
if ! curl -fsSL "https://download.docker.com/linux/ubuntu/gpg" -o "${TEMP_DOCKER_GPG_KEY_DOWNLOAD}"; then
    error "Failed to download Docker/containerd GPG key using curl."
fi

log "Dearmoring GPG key from ${TEMP_DOCKER_GPG_KEY_DOWNLOAD} to ${CONTAINERD_KEYRING_FILE}..."
# Use --batch and --yes for non-interactive operation.
if ! sudo gpg --dearmor --yes --batch -o "${CONTAINERD_KEYRING_FILE}" < "${TEMP_DOCKER_GPG_KEY_DOWNLOAD}"; then
    sudo rm -f "${TEMP_DOCKER_GPG_KEY_DOWNLOAD}" # Clean up temp file
    error "Failed to dearmor Docker/containerd GPG key."
fi
sudo rm -f "${TEMP_DOCKER_GPG_KEY_DOWNLOAD}" # Clean up temp file on success
log "Docker/containerd GPG key successfully processed and stored at ${CONTAINERD_KEYRING_FILE}."

echo "deb [arch=$(dpkg --print-architecture) signed-by=${CONTAINERD_KEYRING_FILE}] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee "${CONTAINERD_REPO_FILE}" > /dev/null || error "Failed to write containerd repo file"

sudo apt-get update
sudo apt-get install -y containerd.io || error "Failed to install containerd.io"
log "containerd.io package installed."

log "Configuring containerd for Kubernetes..."
sudo mkdir -p /etc/containerd
log "Generating default containerd config -> /etc/containerd/config.toml"
sudo bash -c 'containerd config default > /etc/containerd/config.toml'

log "Ensuring CRI plugin is NOT disabled in containerd config..."
# This sed command comments out the line if "cri" is the *only* disabled plugin.
# If other plugins might be listed alongside "cri", a more complex sed or tool might be needed.
sudo sed -i 's/^\s*disabled_plugins\s*=\s*\["cri"\]/#&/' /etc/containerd/config.toml
# Alternative: If 'cri' might be part of a list, e.g., disabled_plugins = ["cri", "other"],
# this would attempt to remove "cri" and an optional comma. This can be tricky with sed.
# sudo sed -i 's/\(\s*disabled_plugins\s*=\s*\[[^]]*\)"cri"\([^,]*,\?\)\([^]]*]\)/\1\2\3/' /etc/containerd/config.toml
# For simplicity, the first sed is often sufficient if "cri" is usually the only one explicitly disabled.

log "Enabling SystemdCgroup in containerd config..."
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

log "Restarting containerd service..."
sudo systemctl restart containerd
log "Enabling containerd service..."
sudo systemctl enable containerd

log "Waiting briefly for containerd socket..."
sleep 5
if [ ! -S /var/run/containerd/containerd.sock ]; then
    warn "containerd socket not found after restart!"
fi
log "Containerd configured and restarted."
# --- End containerd configuration section ---

log "Kubernetes prerequisites setup completed."


# --- Configuration Variables (Path Definitions for NVMe) ---
NVME_MOUNT_POINT="/mnt/nvme_storage"
DEFAULT_AMI_USER="ubuntu" # Or ec2-user, adjust if your base AMI's default user differs

# K8s core directories on NVMe
DEFAULT_CONTAINERD_DIR="/var/lib/containerd"
NVME_CONTAINERD_DIR="${NVME_MOUNT_POINT}/lib/containerd"

DEFAULT_KUBELET_DIR="/var/lib/kubelet"
NVME_KUBELET_DIR="${NVME_MOUNT_POINT}/lib/kubelet"

DEFAULT_K8S_POD_LOGS_DIR="/var/log/pods"
NVME_K8S_POD_LOGS_DIR="${NVME_MOUNT_POINT}/log/pods"

# For TARGET_USER
SHARED_MODELS_BASE_ON_NVME="${NVME_MOUNT_POINT}/shared_data/${TARGET_USER}"
HUGGINGFACE_HOME_ON_NVME="${SHARED_MODELS_BASE_ON_NVME}/huggingface"
DATASETS_PATH_ON_NVME="${SHARED_MODELS_BASE_ON_NVME}/datasets"
LLM_MODELS_PATH_ON_NVME="${SHARED_MODELS_BASE_ON_NVME}/llm_models"
LOCAL_PATH_PROVISIONER_DIR_ON_NVME="${NVME_MOUNT_POINT}/local-path-provisioner"

# User Docker Data (if Docker CE was installed for the TARGET_USER)
USER_DOCKER_DATA_ROOT_ON_NVME="${NVME_MOUNT_POINT}/user_docker_data/${TARGET_USER}"

# --- 1. Detect, Format, and Mount Ephemeral NVMe ---
log "Starting NVMe drive setup..."
ROOT_PARTITION=$(findmnt -n -o SOURCE /) || error "Cannot find root partition."
log "Root partition detected: ${ROOT_PARTITION}"
ROOT_DISK_NAME=$(lsblk -no pkname "${ROOT_PARTITION}")
ROOT_DISK_PATH_PREFIX="/dev/"
ROOT_DISK=""

if [ -n "${ROOT_DISK_NAME}" ]; then
    if [[ ! "${ROOT_DISK_NAME}" == /* ]]; then
      ROOT_DISK="${ROOT_DISK_PATH_PREFIX}${ROOT_DISK_NAME}"
    else
      ROOT_DISK="${ROOT_DISK_NAME}"
    fi
else
    DERIVED_DISK_NAME=$(echo "${ROOT_PARTITION}" | sed -E 's/p[0-9]+$//' | sed -E 's/[0-9]+$//')
    if [[ -n "${DERIVED_DISK_NAME}" && -b "${DERIVED_DISK_NAME}" ]]; then
        ROOT_DISK="${DERIVED_DISK_NAME}"
    elif [[ -b "${ROOT_PARTITION}" ]]; then
        ROOT_DISK="${ROOT_PARTITION}"
    else
        error "Could not confidently determine root disk from root partition ${ROOT_PARTITION}."
    fi
fi
log "Root disk identified as: ${ROOT_DISK}"


TARGET_NVME_DEVICE=""
MIN_SIZE_BYTES=107374182400 # 100 GiB
while read -r DEV TYPE SIZE MOUNTPOINT_LSBLK; do
    log "Checking device for NVMe: Name=${DEV}, Type=${TYPE}, Size=${SIZE}, Mountpoint='${MOUNTPOINT_LSBLK}'"
    if [[ -b "${DEV}" && "${DEV}" == /dev/nvme* && "${TYPE}" == "disk" && "${DEV}" != "${ROOT_DISK}" && "${SIZE}" -gt "${MIN_SIZE_BYTES}" ]]; then
        if [ -z "${MOUNTPOINT_LSBLK}" ] || [ "${MOUNTPOINT_LSBLK}" == "/mnt" ] || [[ "${MOUNTPOINT_LSBLK}" == /media/ephemeral* ]]; then
            log "Found candidate ephemeral NVMe device: ${DEV}"
            TARGET_NVME_DEVICE="${DEV}"
            if [ -n "${MOUNTPOINT_LSBLK}" ] && [ "${MOUNTPOINT_LSBLK}" != "/" ]; then
                log "Unmounting ${DEV} from temporary mount ${MOUNTPOINT_LSBLK}..."
                sudo umount "${DEV}" || warn "Could not unmount ${DEV} from ${MOUNTPOINT_LSBLK}. Proceeding with format."
            fi
            break
        else
            log "Device ${DEV} has unexpected mountpoint '${MOUNTPOINT_LSBLK}'. Skipping."
        fi
    fi
done < <(sudo lsblk -dpbno NAME,TYPE,SIZE,MOUNTPOINT -e 7) # Added sudo to lsblk just in case

if [ -z "${TARGET_NVME_DEVICE}" ]; then
    sudo lsblk -fp # Log full output for debugging if NVMe not found
    error "CRITICAL: Could not dynamically determine a suitable target NVMe device. Ensure instance type has appropriate NVMe instance storage."
fi
NVME_DEVICE="${TARGET_NVME_DEVICE}"
log "Target NVMe device for formatting and use: ${NVME_DEVICE}"

log "Formatting ${NVME_DEVICE} with xfs..."
sudo mkfs.xfs -f "${NVME_DEVICE}" || error "Failed to format ${NVME_DEVICE} with xfs."

sudo mkdir -p "${NVME_MOUNT_POINT}"

log "Mounting ${NVME_DEVICE} to ${NVME_MOUNT_POINT}..."
sudo mount -t xfs -o discard "${NVME_DEVICE}" "${NVME_MOUNT_POINT}" || error "Failed to mount ${NVME_DEVICE} to ${NVME_MOUNT_POINT}."

log "NVMe storage at ${NVME_MOUNT_POINT} is now formatted and mounted."
df -hT "${NVME_MOUNT_POINT}"

# --- 2. Create Directory Structures on Mounted NVMe ---
log "Creating K8s and user data directories on ${NVME_MOUNT_POINT}..."
sudo mkdir -p \
    "${NVME_CONTAINERD_DIR}" \
    "${NVME_KUBELET_DIR}" \
    "${NVME_K8S_POD_LOGS_DIR}" \
    "${HUGGINGFACE_HOME_ON_NVME}" \
    "${DATASETS_PATH_ON_NVME}" \
    "${LLM_MODELS_PATH_ON_NVME}" \
    "${LOCAL_PATH_PROVISIONER_DIR_ON_NVME}" || error "Failed to create one or more base directories on NVMe."

sudo chmod 1777 "${LOCAL_PATH_PROVISIONER_DIR_ON_NVME}"
log "Set permissions for ${LOCAL_PATH_PROVISIONER_DIR_ON_NVME}."

if id "${TARGET_USER}" &>/dev/null; then
    sudo mkdir -p "$(dirname "${SHARED_MODELS_BASE_ON_NVME}")"
    sudo chown "${TARGET_USER}:${TARGET_USER}" "$(dirname "${SHARED_MODELS_BASE_ON_NVME}")" || warn "Failed to chown $(dirname "${SHARED_MODELS_BASE_ON_NVME}")"
    sudo chown -R "${TARGET_USER}:${TARGET_USER}" "${SHARED_MODELS_BASE_ON_NVME}" || warn "Failed to chown -R ${SHARED_MODELS_BASE_ON_NVME}"
    sudo chmod -R u=rwX,g=rX,o= "${SHARED_MODELS_BASE_ON_NVME}"
    log "Set ownership and permissions for ${TARGET_USER}'s shared data directories."
else
    warn "User ${TARGET_USER} not found! Skipping chown for shared data directories."
fi

if [ -f "/etc/docker/daemon.json" ]; then # Check if Docker might be used
    log "Creating user Docker data directory on NVMe: ${USER_DOCKER_DATA_ROOT_ON_NVME}"
    sudo mkdir -p "${USER_DOCKER_DATA_ROOT_ON_NVME}"
    if id "${TARGET_USER}" &>/dev/null; then
        sudo chown -R "${TARGET_USER}:${TARGET_USER}" "${USER_DOCKER_DATA_ROOT_ON_NVME}"
    else
        warn "User ${TARGET_USER} not found! User Docker data directory will be root-owned."
    fi
fi

# --- 3. Stop Services (Temporarily for Symlinking) ---
log "Stopping services temporarily for symlink setup..."
# Check if docker.service unit exists before trying to interact with it
if systemctl list-unit-files | grep -q 'docker.service'; then
    if systemctl is-active --quiet docker; then
        log "Stopping Docker service..."
        sudo systemctl stop docker.socket docker.service || warn "Failed to stop Docker service."
    else
        log "Docker service found but not active."
    fi
else
    log "Docker service unit not found, skipping stop for it."
fi

sudo systemctl stop kubelet || warn "kubelet not running or failed to stop (expected before join)."
sudo systemctl stop containerd || warn "containerd not running or failed to stop."
sleep 3

# --- 4. Create Symlinks ---
create_symlink_if_not_exists() {
    local target_path="$1"
    local link_path="$2"
    local service_name="$3"

    log "Processing symlink for ${service_name}: ${link_path} -> ${target_path}"
    sudo mkdir -p "$(dirname "${link_path}")"

    if [ -L "${link_path}" ]; then
        if [ "$(readlink -f "${link_path}")" = "${target_path}" ]; then
            log "Symlink ${link_path} already exists and is correct for ${service_name}."
            return 0
        else
            warn "Symlink ${link_path} exists but points to $(readlink -f "${link_path}"). Removing and re-creating for ${service_name}."
            sudo rm -f "${link_path}" || warn "Failed to remove existing incorrect symlink ${link_path}"
        fi
    elif [ -e "${link_path}" ]; then
        warn "${link_path} exists but is not a symlink (it's a file or dir). Backing up and re-creating for ${service_name}."
        if [ -d "${link_path}" ] && [ -n "$(ls -A "${link_path}")" ]; then
             sudo mv "${link_path}" "${link_path}.bak_$(date +%s)_userdata" || warn "Failed to backup non-empty ${link_path}"
        elif [ -d "${link_path}" ]; then
             sudo rm -rf "${link_path}" || warn "Failed to remove empty directory ${link_path}"
        else
             sudo mv "${link_path}" "${link_path}.bak_$(date +%s)_userdata" || warn "Failed to backup file ${link_path}"
        fi
    fi

    log "Creating symlink ${link_path} -> ${target_path} for ${service_name}."
    sudo ln -snf "${target_path}" "${link_path}" || error "Failed to create symlink ${link_path} for ${service_name}."
    sudo chown -h root:root "${link_path}"
}

log "Creating symlinks for Kubernetes core directories..."
create_symlink_if_not_exists "${NVME_CONTAINERD_DIR}" "${DEFAULT_CONTAINERD_DIR}" "containerd"
create_symlink_if_not_exists "${NVME_KUBELET_DIR}" "${DEFAULT_KUBELET_DIR}" "kubelet"
create_symlink_if_not_exists "${NVME_K8S_POD_LOGS_DIR}" "${DEFAULT_K8S_POD_LOGS_DIR}" "pod-logs"

# --- 5. Restart Services ---
log "Restarting containerd..."
sudo systemctl start containerd || error "Failed to restart containerd after symlink setup."

if systemctl list-unit-files | grep -q 'docker.service'; then
    if [ -f "/etc/docker/daemon.json" ]; then
        log "Restarting user Docker service..."
        sudo systemctl start docker.socket docker.service || warn "Failed to restart Docker service."
    fi
fi

# --- 6. (Optional) Setup SSH for TARGET_USER ---
# This was done earlier in the script, review if needed here or if earlier placement is sufficient.
# For user_data, earlier might be better if SSH is needed before kubeadm join.

# --- 7. Fetch and Execute kubeadm join ---
log "Fetching kubeadm join command from SSM: ${SSM_JOIN_COMMAND_PATH}"

IMDSV2_TOKEN=""
IMDSV2_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300" || true)

curl_cmd_array=(curl -s)
if [ -n "${IMDSV2_TOKEN}" ]; then
    curl_cmd_array+=(-H "X-aws-ec2-metadata-token: ${IMDSV2_TOKEN}")
else
    warn "Failed to get IMDSv2 token. Proceeding without it. Ensure EC2 instance metadata service is accessible."
fi
curl_cmd_array+=("http://169.254.169.254/latest/dynamic/instance-identity/document")

EC2_REGION=$("${curl_cmd_array[@]}" | jq -r .region)

if [ -z "${EC2_REGION}" ] || [ "${EC2_REGION}" == "null" ]; then
    warn "Failed to determine EC2 region from metadata. Defaulting to us-east-1. Set explicitly if needed."
    EC2_REGION="us-east-1" # Fallback region
fi


if ! command -v aws &> /dev/null; then
    error "AWS CLI not found. This script expects it to be pre-installed or installed by this script."
fi
if ! command -v jq &> /dev/null; then
    error "jq not found. This script expects it to be pre-installed or installed by this script."
fi

log "Fetching join command from SSM Path: ${SSM_JOIN_COMMAND_PATH} in region ${EC2_REGION}"
JOIN_COMMAND=$(aws ssm get-parameter --name "${SSM_JOIN_COMMAND_PATH}" --with-decryption --query Parameter.Value --output text --region "${EC2_REGION}")

if [ -z "${JOIN_COMMAND}" ]; then
    error "Failed to retrieve join command from SSM: ${SSM_JOIN_COMMAND_PATH}"
fi

log "Executing kubeadm join command..."
eval "${JOIN_COMMAND}" # Kubeadm join commands are generally safe for eval, but ensure the source is trusted.
JOIN_EXIT_CODE=$?

if [ ${JOIN_EXIT_CODE} -ne 0 ]; then
    error "kubeadm join command failed with exit code ${JOIN_EXIT_CODE}."
fi

log "kubeadm join command completed successfully."
sleep 10
if systemctl is-active --quiet kubelet; then
    log "Kubelet service is active after join."
else
    warn "Kubelet service is NOT active after join. Check 'journalctl -u kubelet' for errors."
fi

log "Worker node User Data script finished successfully."
exit 0

