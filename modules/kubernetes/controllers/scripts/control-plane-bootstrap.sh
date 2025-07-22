#!/bin/bash
# modules/controllers/scripts/control-plane-bootstrap.sh
# Main control plane bootstrap script - replaces all provisioner logic

set -euo pipefail

#===============================================================================
# Script Arguments and Configuration
#===============================================================================

# Default values
CLUSTER_NAME=""
K8S_USER=""
K8S_VERSION=""
K8S_FULL_VERSION=""
K8S_PACKAGE_SUFFIX=""
POD_CIDR=""
SERVICE_CIDR=""
CONTROLLER_ROLE=""
INSTANCE_ID=""
PRIVATE_IP=""
REGION=""
SSM_JOIN_PATH=""
SSM_CERT_KEY_PATH=""
PRIMARY_CONTROLLER_IP=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --cluster-name) CLUSTER_NAME="$2"; shift 2;;
    --k8s-user) K8S_USER="$2"; shift 2;;
    --k8s-version) K8S_VERSION="$2"; shift 2;;
    --k8s-full-version) K8S_FULL_VERSION="$2"; shift 2;;
    --k8s-package-suffix) K8S_PACKAGE_SUFFIX="$2"; shift 2;;
    --pod-cidr) POD_CIDR="$2"; shift 2;;
    --service-cidr) SERVICE_CIDR="$2"; shift 2;;
    --controller-role) CONTROLLER_ROLE="$2"; shift 2;;
    --instance-id) INSTANCE_ID="$2"; shift 2;;
    --private-ip) PRIVATE_IP="$2"; shift 2;;
    --region) REGION="$2"; shift 2;;
    --ssm-join-path) SSM_JOIN_PATH="$2"; shift 2;;
    --ssm-cert-key-path) SSM_CERT_KEY_PATH="$2"; shift 2;;
    --primary-controller-ip) PRIMARY_CONTROLLER_IP="$2"; shift 2;;
    *) echo "Unknown option $1"; exit 1;;
  esac
done

# Validate required arguments
if [ -z "$CLUSTER_NAME" ] || [ -z "$K8S_USER" ] || [ -z "$CONTROLLER_ROLE" ]; then
    echo "FATAL: Missing required arguments"
    exit 1
fi

#===============================================================================
# Logging Setup
#===============================================================================

LOG_FILE="/var/log/control-plane-bootstrap.log"
touch "${LOG_FILE}"
chmod 644 "${LOG_FILE}"
exec > >(tee -a "${LOG_FILE}") 2>&1

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log() { echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
error() { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; exit 1; }
step() { echo -e "${BLUE}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }

log "=== Control Plane Bootstrap Started ==="
log "Cluster: $CLUSTER_NAME, Role: $CONTROLLER_ROLE, Instance: $INSTANCE_ID ($PRIVATE_IP)"
log "K8s Version: $K8S_FULL_VERSION, Pod CIDR: $POD_CIDR, Service CIDR: $SERVICE_CIDR"

#===============================================================================
# Stage 1: System Setup & Kubernetes Package Installation
#===============================================================================
step "Stage 1: System setup and Kubernetes installation"

log "Updating apt packages..."
apt-get update -y

log "Installing required packages: apt-transport-https, ca-certificates, curl, gpg"
apt-get install -y apt-transport-https ca-certificates curl gpg

log "Adding Kubernetes apt repository key..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

log "Adding Kubernetes apt repository..."
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

log "Updating apt packages again..."
apt-get update -y

K8S_PACKAGE_VERSION="${K8S_FULL_VERSION}${K8S_PACKAGE_SUFFIX}"
log "Installing Kubernetes packages: kubelet=${K8S_PACKAGE_VERSION}, kubeadm=${K8S_PACKAGE_VERSION}, kubectl=${K8S_PACKAGE_VERSION}"
apt-get install -y kubelet=${K8S_PACKAGE_VERSION} kubeadm=${K8S_PACKAGE_VERSION} kubectl=${K8S_PACKAGE_VERSION}
apt-mark hold kubelet kubeadm kubectl

log "Enabling and starting kubelet service..."
systemctl enable --now kubelet

log "Configuring containerd..."
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd

log "Kubernetes packages installed successfully."

#===============================================================================
# Stage 2: Control Plane Bootstrap
#===============================================================================
step "Stage 2: Control plane bootstrap"

if [ "$CONTROLLER_ROLE" = "primary" ]; then
    log "Bootstrapping PRIMARY control plane node..."
    
    log "Creating kubeadm configuration..."
    cat <<EOF > /tmp/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  kubeletExtraArgs:
    cloud-provider: "aws"
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: "${K8S_FULL_VERSION}"
clusterName: "${CLUSTER_NAME}"
controlPlaneEndpoint: "${PRIVATE_IP}:6443"
apiServer:
  certSANs:
  - "${PRIVATE_IP}"
networking:
  podSubnet: "${POD_CIDR}"
  serviceSubnet: "${SERVICE_CIDR}"
EOF

    log "Running 'kubeadm init'..."
    kubeadm init --config /tmp/kubeadm-config.yaml --upload-certs

    log "Control plane initialization completed."

else
    log "Bootstrapping SECONDARY control plane node..."
    
    log "Waiting for primary node to upload join command to SSM..."
    JOIN_COMMAND=""
    CERT_KEY=""
    for i in {1..30}; do
        log "Attempt $i/30: Checking for join command in SSM..."
        JOIN_COMMAND=$(aws ssm get-parameter --name "${SSM_JOIN_PATH}" --with-decryption --region "${REGION}" --query "Parameter.Value" --output text 2>/dev/null)
        CERT_KEY=$(aws ssm get-parameter --name "${SSM_CERT_KEY_PATH}" --with-decryption --region "${REGION}" --query "Parameter.Value" --output text 2>/dev/null)
        if [[ -n "$JOIN_COMMAND" && -n "$CERT_KEY" ]]; then
            log "Successfully retrieved join command and certificate key from SSM."
            break
        fi
        sleep 20
    done

    if [[ -z "$JOIN_COMMAND" || -z "$CERT_KEY" ]]; then
        error "Failed to retrieve join command or certificate key from SSM after multiple attempts."
    fi

    log "Joining the cluster as a control plane node..."
    eval "$JOIN_COMMAND --control-plane --certificate-key $CERT_KEY"
    log "Successfully joined the cluster."
fi

#===============================================================================
# Stage 3: Post-Bootstrap Configuration
#===============================================================================
step "Stage 3: Post-bootstrap configuration"

log "Configuring kubectl for the root and ${K8S_USER} users..."
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config

mkdir -p /home/${K8S_USER}/.kube
cp -i /etc/kubernetes/admin.conf /home/${K8S_USER}/.kube/config
chown ${K8S_USER}:${K8S_USER} /home/${K8S_USER}/.kube/config

log "Kubectl configured."

#===============================================================================
# Stage 4: Apply CNI and Upload Join Commands (Primary Only)
#===============================================================================
if [ "$CONTROLLER_ROLE" = "primary" ]; then
    step "Stage 4: Applying CNI and uploading join commands"

    log "Applying Calico CNI..."
    kubectl --kubeconfig /etc/kubernetes/admin.conf create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml
    
    # Wait a moment for the operator to be ready
    sleep 30

    cat <<EOF | kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: ${POD_CIDR}
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
EOF
    log "Calico CNI applied."

    log "Generating and uploading worker join command to SSM..."
    WORKER_JOIN_COMMAND=$(kubeadm token create --print-join-command)
    if [ -n "$WORKER_JOIN_COMMAND" ]; then
        aws ssm put-parameter --region "$REGION" --name "$SSM_JOIN_PATH" --value "$WORKER_JOIN_COMMAND" --type "SecureString" --overwrite
        log "Worker join command uploaded to SSM: $SSM_JOIN_PATH"
    else
        error "Failed to generate worker join command."
    fi
    
    log "Generating and uploading certificate key to SSM..."
    CERT_KEY=$(kubeadm init phase upload-certs --upload-certs | tail -n 1)
    if [ -n "$CERT_KEY" ]; then
        aws ssm put-parameter --region "$REGION" --name "$SSM_CERT_KEY_PATH" --value "$CERT_KEY" --type "SecureString" --overwrite
        log "Certificate key uploaded to SSM: $SSM_CERT_KEY_PATH"
    else
        error "Failed to generate certificate key."
    fi
fi

#===============================================================================
# Final Steps and Verification
#===============================================================================
step "Final verification"

log "Waiting for this node to be Ready..."
for i in {1..30}; do
    if kubectl --kubeconfig /etc/kubernetes/admin.conf get node $(hostname | tr '[:upper:]' '[:lower:]') --no-headers 2>/dev/null | grep -q "Ready"; then
        log "Node $(hostname) is Ready."
        break
    fi
    log "Waiting for node to be Ready... (attempt $i/30)"
    sleep 10
done

if ! kubectl --kubeconfig /etc/kubernetes/admin.conf get node $(hostname | tr '[:upper:]' '[:lower:]') --no-headers 2>/dev/null | grep -q "Ready"; then
    error "Node did not become Ready in time."
fi

log "Verifying cluster health..."
kubectl --kubeconfig /etc/kubernetes/admin.conf get nodes -o wide
kubectl --kubeconfig /etc/kubernetes/admin.conf get pods -A -o wide

touch /var/lib/kubernetes-bootstrap-complete
log "=== Control Plane Bootstrap Completed Successfully ==="
exit 0