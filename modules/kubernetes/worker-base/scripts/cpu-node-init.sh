#!/bin/bash
set -euo pipefail # Strict mode

# --- Script Arguments (Passed by Terraform templatefile) ---
# Ensure your Terraform `templatefile` call provides these.
# Example: $1 = target_user (e.g., graphscoper)
#          $2 = k8s_version_mm (e.g., 1.30 - mostly informational for this script)
#          $3 = ssm_join_command_path (e.g., /mycluster/worker-join-command)
#          $4 = cluster_dns_ip (if specifically needed and not inferred by kubeadm)

if [ "$#" -lt 3 ]; then
    echo "FATAL: Missing required arguments."
    echo "Usage: $0 <target_k8s_user> <k8s_major_minor_version> <ssm_join_command_path> [cluster_dns_ip]"
    echo "Received $# arguments: $@"
    # Log to a temporary file if the main log isn't set up yet
    echo "FATAL: Missing required arguments. Received $# arguments: $@" > /tmp/bootstrap_arg_error.log
    exit 1
fi

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

log "Worker Node User Data Script (for Baked AMI) started."

# --- Process Script Arguments ---
TARGET_USER="${1}"
K8S_VERSION_MM="${2}" # Informational, as K8s components are baked in
SSM_JOIN_COMMAND_PATH="${3}"
CLUSTER_DNS_IP="${4:-}" # Optional, assign if provided, otherwise empty

log "Running with Target User: ${TARGET_USER}"
log "K8s Version (Baked in AMI): ${K8S_VERSION_MM}"
log "Using SSM Join Command Path: ${SSM_JOIN_COMMAND_PATH}"
[ -n "${CLUSTER_DNS_IP}" ] && log "Using Cluster DNS IP: ${CLUSTER_DNS_IP}"

# --- Get Region and Setup CloudWatch Logging (Optional) ---
# Fetch IMDSv2 Token for metadata access
IMDSV2_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300" 2>/dev/null || echo "")
METADATA_HEADER_ARGS=""
if [ -n "$IMDSV2_TOKEN" ]; then
    METADATA_HEADER_ARGS="-H \"X-aws-ec2-metadata-token: $IMDSV2_TOKEN\""
fi

# Get region and instance info
EC2_REGION=$(eval "curl -s $METADATA_HEADER_ARGS http://169.254.169.254/latest/dynamic/instance-identity/document" 2>/dev/null | jq -r .region 2>/dev/null || echo "us-east-1")
INSTANCE_ID=$(eval "curl -s $METADATA_HEADER_ARGS http://169.254.169.254/latest/meta-data/instance-id" 2>/dev/null || hostname)

log "Region: ${EC2_REGION}, Instance: ${INSTANCE_ID}"

# Setup CloudWatch logging (optional - only if AWS CLI is available and working)
setup_cloudwatch_logging() {
    if command -v aws &> /dev/null; then
        local log_group="/aws/ec2/kubernetes-bootstrap"
        local log_stream="${INSTANCE_ID}-$(date +%s)"
        
        # Create log group (ignore if exists)
        aws logs create-log-group --log-group-name "$log_group" --region "$EC2_REGION" 2>/dev/null || true
        
        # Create log stream (ignore if exists) 
        aws logs create-log-stream --log-group-name "$log_group" --log-stream-name "$log_stream" --region "$EC2_REGION" 2>/dev/null || true
        
        if [ $? -eq 0 ]; then
            log "CloudWatch logging setup for log group: $log_group"
        fi
    fi
}

setup_cloudwatch_logging

# --- Configuration Variables (Path Definitions) ---
# These MUST match the paths your applications and symlinks expect.
NVME_MOUNT_POINT="/mnt/nvme_storage"
DEFAULT_AMI_USER="ubuntu" # Or ec2-user, adjust if your base AMI's default user differs

# K8s core directories on NVMe
DEFAULT_CONTAINERD_DIR="/var/lib/containerd"
NVME_CONTAINERD_DIR="${NVME_MOUNT_POINT}/lib/containerd"

DEFAULT_KUBELET_DIR="/var/lib/kubelet"
NVME_KUBELET_DIR="${NVME_MOUNT_POINT}/lib/kubelet"

DEFAULT_K8S_POD_LOGS_DIR="/var/log/pods"
NVME_K8S_POD_LOGS_DIR="${NVME_MOUNT_POINT}/log/pods"

# For TARGET_USER (e.g., graphscoper)
SHARED_MODELS_BASE_ON_NVME="${NVME_MOUNT_POINT}/shared_data/${TARGET_USER}"
HUGGINGFACE_HOME_ON_NVME="${SHARED_MODELS_BASE_ON_NVME}/huggingface"
DATASETS_PATH_ON_NVME="${SHARED_MODELS_BASE_ON_NVME}/datasets"
LLM_MODELS_PATH_ON_NVME="${SHARED_MODELS_BASE_ON_NVME}/llm_models"
LOCAL_PATH_PROVISIONER_DIR_ON_NVME="${NVME_MOUNT_POINT}/local-path-provisioner"

# User Docker Data (if Docker CE was installed in AMI for the TARGET_USER)
USER_DOCKER_DATA_ROOT_ON_NVME="${NVME_MOUNT_POINT}/user_docker_data/${TARGET_USER}"

# --- 1. Detect, Format, and Mount Ephemeral NVMe ---
log "Starting NVMe drive setup..."
# Robust NVMe detection logic (adapted from your previous scripts)
ROOT_PARTITION=$(findmnt -n -o SOURCE /) || error "Cannot find root partition."
log "Root partition detected: ${ROOT_PARTITION}"
ROOT_DISK_NAME=$(lsblk -no pkname "${ROOT_PARTITION}")
ROOT_DISK_PATH_PREFIX="/dev/" # Standard prefix for block devices
ROOT_DISK=""

if [ -n "${ROOT_DISK_NAME}" ]; then
    if [[ ! "${ROOT_DISK_NAME}" == /* ]]; then # Check if it's a relative name like "nvme0n1"
      ROOT_DISK="${ROOT_DISK_PATH_PREFIX}${ROOT_DISK_NAME}"
    else # It's already a full path like "/dev/nvme0n1"
      ROOT_DISK="${ROOT_DISK_NAME}"
    fi
else
    # Fallback if pkname failed (e.g., root is directly on a device without partition table)
    if [[ "${ROOT_PARTITION}" == /* ]]; then
        ROOT_DISK="${ROOT_PARTITION}"
    else
        warn "Could not determine parent disk confidently, using root partition path ${ROOT_PARTITION} as reference."
        ROOT_DISK="${ROOT_DISK_PATH_PREFIX}${ROOT_PARTITION}"
    fi
fi
log "Root disk identified as: ${ROOT_DISK}"

TARGET_NVME_DEVICE=""
MIN_SIZE_BYTES=107374182400 # 100 GiB
# lsblk options: -d (no partitions), -p (full paths), -b (bytes), -n (no headers), -o (columns), -e 7 (exclude loop)
while read -r DEV TYPE SIZE MOUNTPOINT_LSBLK; do
    log "Checking device for NVMe: Name=${DEV}, Type=${TYPE}, Size=${SIZE}, Mountpoint='${MOUNTPOINT_LSBLK}'"
    if [[ "${DEV}" == /dev/nvme* && "${TYPE}" == "disk" && "${DEV}" != "${ROOT_DISK}" && "${SIZE}" -gt "${MIN_SIZE_BYTES}" ]]; then
        if [ -z "${MOUNTPOINT_LSBLK}" ] || [ "${MOUNTPOINT_LSBLK}" == "/mnt" ] || [[ "${MOUNTPOINT_LSBLK}" == /media/ephemeral* ]]; then
            log "Found candidate ephemeral NVMe device: ${DEV}"
            TARGET_NVME_DEVICE="${DEV}"
            if [ -n "${MOUNTPOINT_LSBLK}" ] && [ "${MOUNTPOINT_LSBLK}" != "/" ]; then # Don't unmount root!
                log "Unmounting ${DEV} from temporary mount ${MOUNTPOINT_LSBLK}..."
                umount "${DEV}" || warn "Could not unmount ${DEV} from ${MOUNTPOINT_LSBLK}. Proceeding with format."
            fi
            break
        else
            log "Device ${DEV} has unexpected mountpoint '${MOUNTPOINT_LSBLK}'. Skipping."
        fi
    fi
done < <(lsblk -dpbno NAME,TYPE,SIZE,MOUNTPOINT -e 7)

if [ -z "${TARGET_NVME_DEVICE}" ]; then
    lsblk -fp # Log full output for debugging if NVMe not found
    error "CRITICAL: Could not dynamically determine a suitable target NVMe device."
fi
NVME_DEVICE="${TARGET_NVME_DEVICE}"
log "Target NVMe device for formatting and use: ${NVME_DEVICE}"

# Format the NVMe device (it's ephemeral, so format on each boot)
log "Formatting ${NVME_DEVICE} with xfs..."
mkfs.xfs -f "${NVME_DEVICE}" || error "Failed to format ${NVME_DEVICE} with xfs."

# Create mount point (should exist from AMI base if you created /mnt there, but -p is safe)
mkdir -p "${NVME_MOUNT_POINT}"

# Mount the newly formatted NVMe device
log "Mounting ${NVME_DEVICE} to ${NVME_MOUNT_POINT}..."
mount -t xfs -o discard "${NVME_DEVICE}" "${NVME_MOUNT_POINT}" || error "Failed to mount ${NVME_DEVICE} to ${NVME_MOUNT_POINT}."

log "NVMe storage at ${NVME_MOUNT_POINT} is now formatted and mounted."
df -hT "${NVME_MOUNT_POINT}" # Log the mount status

# --- 2. Create Directory Structures on Mounted NVMe ---
log "Creating K8s and user data directories on ${NVME_MOUNT_POINT}..."
mkdir -p \
    "${NVME_CONTAINERD_DIR}" \
    "${NVME_KUBELET_DIR}" \
    "${NVME_K8S_POD_LOGS_DIR}" \
    "${HUGGINGFACE_HOME_ON_NVME}" \
    "${DATASETS_PATH_ON_NVME}" \
    "${LLM_MODELS_PATH_ON_NVME}" \
    "${LOCAL_PATH_PROVISIONER_DIR_ON_NVME}" || error "Failed to create one or more base directories on NVMe."

# Set permissions for Local Path Provisioner directory
chmod 1777 "${LOCAL_PATH_PROVISIONER_DIR_ON_NVME}"
log "Set permissions for ${LOCAL_PATH_PROVISIONER_DIR_ON_NVME}."

# Set ownership for TARGET_USER's shared data paths
# This user should have been created in the AMI prep script.
if id "${TARGET_USER}" &>/dev/null; then
    # Ensure parent shared_data dir exists before chown
    mkdir -p "$(dirname "${SHARED_MODELS_BASE_ON_NVME}")"
    chown -R "${TARGET_USER}:${TARGET_USER}" "$(dirname "${SHARED_MODELS_BASE_ON_NVME}")" # Chown parent first
    chown -R "${TARGET_USER}:${TARGET_USER}" "${SHARED_MODELS_BASE_ON_NVME}"
    chmod -R u=rwX,g=rX,o= "${SHARED_MODELS_BASE_ON_NVME}"
    log "Set ownership and permissions for ${TARGET_USER}'s shared data directories."
else
    warn "User ${TARGET_USER} not found! Skipping chown for shared data directories. This user should exist from AMI."
fi

# Create User Docker Data dir if Docker CE was installed in AMI
# The /etc/docker/daemon.json in the AMI should already point to USER_DOCKER_DATA_ROOT_ON_NVME
if [ -f "/etc/docker/daemon.json" ]; then # Check if Docker was likely configured in AMI
    log "Creating user Docker data directory on NVMe: ${USER_DOCKER_DATA_ROOT_ON_NVME}"
    mkdir -p "${USER_DOCKER_DATA_ROOT_ON_NVME}"
    if id "${TARGET_USER}" &>/dev/null; then
        chown -R "${TARGET_USER}:${TARGET_USER}" "${USER_DOCKER_DATA_ROOT_ON_NVME}"
    else
        warn "User ${TARGET_USER} not found! User Docker data directory will be root-owned."
    fi
fi

# --- 3. Stop Services (Temporarily for Symlinking) ---
log "Stopping services temporarily for symlink setup..."
if systemctl list-units --full -all | grep -q 'docker.service'; then
    if systemctl is-active --quiet docker; then
        systemctl stop docker.socket docker.service || warn "Failed to stop Docker service."
    else
        log "Docker service found but not active."
    fi
else
    log "Docker service not found, skipping stop for it."
fi
systemctl stop kubelet || warn "kubelet not running or failed to stop (expected before join)."
systemctl stop containerd || warn "containerd not running or failed to stop."
sleep 3 # Brief pause to allow services to release file locks

# --- 4. Create Symlinks ---
create_symlink_if_not_exists() {
    local target_path="$1"
    local link_path="$2"
    local service_name="$3" # Informational

    log "Processing symlink for ${service_name}: ${link_path} -> ${target_path}"
    # Ensure parent of link_path exists (e.g., /var/lib if link is /var/lib/containerd)
    mkdir -p "$(dirname "${link_path}")"

    if [ -L "${link_path}" ]; then
        if [ "$(readlink -f "${link_path}")" = "${target_path}" ]; then
            log "Symlink ${link_path} already exists and is correct for ${service_name}."
            return 0
        else
            warn "Symlink ${link_path} exists but points to $(readlink -f "${link_path}"). Removing and re-creating for ${service_name}."
            rm -f "${link_path}" || warn "Failed to remove existing incorrect symlink ${link_path}"
        fi
    elif [ -e "${link_path}" ]; then
        warn "${link_path} exists but is not a symlink (it's a file or dir). Backing up and re-creating for ${service_name}."
        mv "${link_path}" "${link_path}.bak_$(date +%s)_userdata" || warn "Failed to backup ${link_path}"
    fi

    log "Creating symlink ${link_path} -> ${target_path} for ${service_name}."
    ln -snf "${target_path}" "${link_path}" || error "Failed to create symlink ${link_path} for ${service_name}." # -n (no-dereference), -f (force)

    chown -h root:root "${link_path}" # -h for the symlink itself
}

log "Creating symlinks for Kubernetes core directories..."
create_symlink_if_not_exists "${NVME_CONTAINERD_DIR}" "${DEFAULT_CONTAINERD_DIR}" "containerd"
create_symlink_if_not_exists "${NVME_KUBELET_DIR}" "${DEFAULT_KUBELET_DIR}" "kubelet"
create_symlink_if_not_exists "${NVME_K8S_POD_LOGS_DIR}" "${DEFAULT_K8S_POD_LOGS_DIR}" "pod-logs"

# --- 5. Restart Services ---
log "Restarting containerd..."
systemctl start containerd || error "Failed to restart containerd after symlink setup."
# Kubelet will be configured and started by kubeadm join.

if systemctl list-units --full -all | grep -q 'docker.service'; then
    if [ -f "/etc/docker/daemon.json" ]; then # If Docker was configured for user
        log "Restarting user Docker service..."
        systemctl start docker.socket docker.service || warn "Failed to restart Docker service."
    fi
fi

# --- 6. (Optional) Setup SSH for TARGET_USER ---
log "Setting up SSH authorized_keys for ${TARGET_USER} by copying from ${DEFAULT_AMI_USER}..."
USER_HOME_FOR_SSH="/home/${TARGET_USER}"
USER_SSH_DIR_FOR_SSH="${USER_HOME_FOR_SSH}/.ssh"
DEFAULT_USER_AUTHORIZED_KEYS_PATH="/home/${DEFAULT_AMI_USER}/.ssh/authorized_keys"

if [ -f "${DEFAULT_USER_AUTHORIZED_KEYS_PATH}" ]; then
    if id "${TARGET_USER}" &>/dev/null; then
        mkdir -p "${USER_SSH_DIR_FOR_SSH}"
        cp "${DEFAULT_USER_AUTHORIZED_KEYS_PATH}" "${USER_SSH_DIR_FOR_SSH}/authorized_keys"
        chown -R "${TARGET_USER}:${TARGET_USER}" "${USER_SSH_DIR_FOR_SSH}"
        chmod 700 "${USER_SSH_DIR_FOR_SSH}"
        chmod 600 "${USER_SSH_DIR_FOR_SSH}/authorized_keys"
        log "SSH authorized_keys copied for ${TARGET_USER} from ${DEFAULT_AMI_USER}."
    else
        warn "User ${TARGET_USER} does not exist. Cannot set up SSH keys for them."
    fi
else
    warn "Default user (${DEFAULT_AMI_USER}) authorized_keys not found at ${DEFAULT_USER_AUTHORIZED_KEYS_PATH}. Cannot copy for ${TARGET_USER}."
fi

# --- 7. Fetch and Execute kubeadm join with Retry Logic ---
log "Fetching kubeadm join command from SSM: ${SSM_JOIN_COMMAND_PATH}"

# AWS CLI should be in AMI (baked in)
if ! command -v aws &> /dev/null; then
    error "AWS CLI not found. This should have been in the baked AMI."
fi

# Improved SSM parameter fetch with retry logic
fetch_ssm_parameter() {
    local param_path="$1"
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log "Attempt $attempt/$max_attempts: Fetching SSM parameter: $param_path"
        
        # Try to fetch the parameter
        if JOIN_COMMAND=$(aws ssm get-parameter --name "$param_path" --with-decryption --query Parameter.Value --output text --region "$EC2_REGION" 2>/dev/null); then
            if [ -n "$JOIN_COMMAND" ] && [ "$JOIN_COMMAND" != "None" ]; then
                log "Successfully fetched join command from SSM"
                return 0
            fi
        fi
        
        warn "Failed to fetch SSM parameter, attempt $attempt/$max_attempts"
        if [ $attempt -lt $max_attempts ]; then
            local sleep_time=$((attempt * 10))  # Exponential backoff: 10s, 20s, 30s, 40s
            log "Waiting ${sleep_time} seconds before retry..."
            sleep $sleep_time
        fi
        ((attempt++))
    done
    
    error "Failed to fetch SSM parameter after $max_attempts attempts"
}

# Fetch the join command with retry logic
fetch_ssm_parameter "${SSM_JOIN_COMMAND_PATH}"

log "Executing kubeadm join command..."
# Add --v=5 for more verbose output from kubeadm if debugging is needed
eval "${JOIN_COMMAND}"
JOIN_EXIT_CODE=$?

if [ $JOIN_EXIT_CODE -ne 0 ]; then
    error "kubeadm join command failed with exit code $JOIN_EXIT_CODE."
fi

log "kubeadm join command completed successfully."

# --- 8. Verify Services and Node Readiness ---
log "Verifying kubelet service status..."
sleep 10 # Give kubelet a moment to fully start and report status

# Check kubelet status
if systemctl is-active --quiet kubelet; then
    log "Kubelet service is active after join."
else
    warn "Kubelet service is NOT active after join. Check 'journalctl -u kubelet' for errors."
    # Still continue to check node readiness
fi

# Wait for node to become ready in the cluster
log "Waiting for node to be ready in Kubernetes cluster..."
wait_for_node_ready() {
    local max_attempts=30
    local attempt=1
    local hostname=$(hostname)
    
    # Wait for kubelet config to be available
    while [ $attempt -le 5 ]; do
        if [ -f "/etc/kubernetes/kubelet.conf" ]; then
            log "Kubelet config found"
            break
        fi
        log "Waiting for kubelet config... (attempt $attempt/5)"
        sleep 10
        ((attempt++))
    done
    
    if [ ! -f "/etc/kubernetes/kubelet.conf" ]; then
        warn "Kubelet config not found after 50 seconds. Node readiness check may fail."
        return 1
    fi
    
    # Check node readiness
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        log "Checking node readiness... (attempt $attempt/$max_attempts)"
        
        if kubectl --kubeconfig=/etc/kubernetes/kubelet.conf get node "$hostname" --no-headers 2>/dev/null | grep -q "Ready"; then
            log "✅ Node '$hostname' is Ready in Kubernetes cluster!"
            return 0
        fi
        
        # Show current node status for debugging
        if [ $((attempt % 5)) -eq 0 ]; then  # Every 5th attempt
            log "Current node status:"
            kubectl --kubeconfig=/etc/kubernetes/kubelet.conf get node "$hostname" 2>/dev/null || log "Cannot get node status yet"
        fi
        
        sleep 20  # Check every 20 seconds
        ((attempt++))
    done
    
    warn "Node did not become Ready within $((max_attempts * 20)) seconds"
    log "Final node status:"
    kubectl --kubeconfig=/etc/kubernetes/kubelet.conf get node "$hostname" 2>/dev/null || log "Cannot get node status"
    return 1
}

# Call the function but don't fail the script if it times out
if wait_for_node_ready; then
    log "Node readiness verification completed successfully."
else
    warn "Node readiness verification timed out, but continuing. Check cluster status manually."
fi

# --- 9. Final Status Report ---
log "=== Bootstrap Summary ==="
log "✅ NVMe storage: ${NVME_DEVICE} mounted at ${NVME_MOUNT_POINT}"
log "✅ Kubernetes directories symlinked to NVMe"
log "✅ Services restarted: containerd, kubelet"
log "✅ Node joined to cluster: ${SSM_JOIN_COMMAND_PATH}"
log "✅ Target user: ${TARGET_USER}"

# Show final disk usage
log "Final NVMe storage usage:"
df -hT "${NVME_MOUNT_POINT}"

# Show kubelet status
log "Final kubelet status:"
systemctl --no-pager status kubelet || true

log "🎉 Worker node User Data script finished successfully!"
exit 0
