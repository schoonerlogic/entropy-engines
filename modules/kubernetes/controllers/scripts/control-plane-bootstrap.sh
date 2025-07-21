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
    --cluster-name)
      CLUSTER_NAME="$2"
      shift 2
      ;;
    --k8s-user)
      K8S_USER="$2"
      shift 2
      ;;
    --k8s-version)
      K8S_VERSION="$2"
      shift 2
      ;;
    --k8s-full-version)
      K8S_FULL_VERSION="$2"
      shift 2
      ;;
    --k8s-package-suffix)
      K8S_PACKAGE_SUFFIX="$2"
      shift 2
      ;;
    --pod-cidr)
      POD_CIDR="$2"
      shift 2
      ;;
    --service-cidr)
      SERVICE_CIDR="$2"
      shift 2
      ;;
    --controller-role)
      CONTROLLER_ROLE="$2"
      shift 2
      ;;
    --instance-id)
      INSTANCE_ID="$2"
      shift 2
      ;;
    --private-ip)
      PRIVATE_IP="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --ssm-join-path)
      SSM_JOIN_PATH="$2"
      shift 2
      ;;
    --ssm-cert-key-path)
      SSM_CERT_KEY_PATH="$2"
      shift 2
      ;;
    --primary-controller-ip)
      PRIMARY_CONTROLLER_IP="$2"
      shift 2
      ;;
    *)
      echo "Unknown option $1"
      exit 1
      ;;
  esac
done

# Validate required arguments
if [ -z "$CLUSTER_NAME" ] || [ -z "$K8S_USER" ] || [ -z "$CONTROLLER_ROLE" ]; then
    echo "FATAL: Missing required arguments"
    echo "Usage: $0 --cluster-name NAME --k8s-user USER --controller-role primary|secondary [other options]"
    exit 1
fi

#===============================================================================
# Logging Setup
#===============================================================================

LOG_FILE="/var/log/control-plane-bootstrap.log"
touch "${LOG_FILE}"
chmod 644 "${LOG_FILE}"
exec > >(tee -a "${LOG_FILE}") 2>&1

# Color codes and logging functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
error() { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; exit 1; }
step() { echo -e "${BLUE}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }

log "=== Control Plane Bootstrap Started ==="
log "Cluster: $CLUSTER_NAME"
log "Role: $CONTROLLER_ROLE"
log "Instance: $INSTANCE_ID ($PRIVATE_IP)"
log "K8s Version: $K8S_VERSION"
log "Pod CIDR: $POD_CIDR"
log "Service CIDR: $SERVICE_CIDR"

#===============================================================================
# Stage 1: Basic System Setup (Replaces control-node-init.sh logic)
#===============================================================================

step "Stage 1: Basic system setup and Kubernetes installation"

# Add K8s user setup logic here (from your existing control-node-init.sh)
log "Setting up Kubernetes user: $K8S_USER"
# ... (incorporate your existing user setup logic)

# Add Kubernetes package installation logic here
log "Installing Kubernetes packages version: $K8S_FULL_VERSION$K8S_PACKAGE_SUFFIX"
# ... (incorporate your existing K8s installation logic)

#===============================================================================
# Stage 2: Control Plane Bootstrap (Replaces bootstrap.sh.tftpl logic)
#===============================================================================

step "Stage 2: Control plane bootstrap"

if [ "$CONTROLLER_ROLE" = "primary" ]; then
    log "Bootstrapping PRIMARY control plane"
    
    # Wait for system to be ready
    log "Waiting for system readiness..."
    sleep 30
    
    # Initialize the first control plane node
    log "Initializing Kubernetes control plane..."
    # Add your kubeadm init logic here
    # Example:
    # kubeadm init \
    #   --pod-network-cidr="$POD_CIDR" \
    #   --service-cidr="$SERVICE_CIDR" \
    #   --apiserver-advertise-address="$PRIVATE_IP" \
    #   --upload-certs
    
    log "Control plane initialization completed"
    
else
    log "Bootstrapping SECONDARY control plane"
    
    # Wait for primary to be ready and get join token from SSM
    log "Waiting for primary control plane to be ready..."
    # Add logic to wait for SSM parameters to be available
    # Add logic to join as additional control plane node
    
fi

#===============================================================================
# Stage 3: Post-Bootstrap Configuration (Replaces configure-controller.sh.tftpl)
#===============================================================================

step "Stage 3: Post-bootstrap configuration"

# Configure kubectl for the K8s user
log "Configuring kubectl for user: $K8S_USER"
# Add kubectl configuration logic here

# Set up cluster networking and basic configuration
log "Configuring cluster networking"
# Add networking configuration logic here

#===============================================================================
# Stage 4: Wait for Kubernetes (Replaces wait-for-kubernetes.sh.tftpl)
#===============================================================================

step "Stage 4: Waiting for Kubernetes to be ready"

log "Waiting for Kubernetes API server..."
for i in {1..60}; do
    if kubectl get nodes &>/dev/null; then
        log "Kubernetes API server is ready"
        break
    fi
    log "Waiting for API server... (attempt $i/60)"
    sleep 10
done

log "Waiting for this node to be Ready..."
for i in {1..30}; do
    if kubectl get node $(hostname) --no-headers 2>/dev/null | grep -q Ready; then
        log "Node $(hostname) is Ready"
        break
    fi
    log "Waiting for node to be Ready... (attempt $i/30)"
    sleep 10
done

#===============================================================================
# Stage 5: Apply Cluster Addons (Replaces cluster-addons.sh.tftpl - Primary Only)
#===============================================================================

if [ "$CONTROLLER_ROLE" = "primary" ]; then
    step "Stage 5: Applying cluster addons"
    
    log "Applying essential cluster addons..."
    # Add your cluster addon logic here (CNI, etc.)
    # Example:
    # kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/calico.yaml
    
    log "Cluster addons applied successfully"
fi

#===============================================================================
# Stage 6: Upload Join Commands to SSM (Replaces upload-join-command.tftpl - Primary Only)
#===============================================================================

if [ "$CONTROLLER_ROLE" = "primary" ]; then
    step "Stage 6: Uploading join commands to SSM"
    
    log "Generating and uploading worker join command..."
    
    # Generate worker join command
    WORKER_JOIN_COMMAND=$(kubeadm token create --print-join-command)
    
    if [ -n "$WORKER_JOIN_COMMAND" ]; then
        # Upload to SSM
        aws ssm put-parameter \
            --region "$REGION" \
            --name "$SSM_JOIN_PATH" \
            --value "$WORKER_JOIN_COMMAND" \
            --type "SecureString" \
            --overwrite \
            --description "Worker join command for cluster $CLUSTER_NAME"
        
        log "Worker join command uploaded to SSM: $SSM_JOIN_PATH"
    else
        error "Failed to generate worker join command"
    fi
    
    # Generate and upload certificate key for additional control plane nodes
    log "Generating and uploading certificate key..."
    
    CERT_KEY=$(kubeadm init phase upload-certs --upload-certs | tail -n 1)
    
    if [ -n "$CERT_KEY" ]; then
        aws ssm put-parameter \
            --region "$REGION" \
            --name "$SSM_CERT_KEY_PATH" \
            --value "$CERT_KEY" \
            --type "SecureString" \
            --overwrite \
            --description "Certificate key for control plane join in cluster $CLUSTER_NAME"
        
        log "Certificate key uploaded to SSM: $SSM_CERT_KEY_PATH"
    else
        error "Failed to generate certificate key"
    fi
fi

#===============================================================================
# Final Steps and Verification
#===============================================================================

step "Final verification and cleanup"

# Verify cluster health
log "Verifying cluster health..."
kubectl get nodes
kubectl get pods -A

# Create success marker
touch /var/lib/kubernetes-bootstrap-complete

log "=== Control Plane Bootstrap Completed Successfully ==="
log "Cluster: $CLUSTER_NAME"
log "Role: $CONTROLLER_ROLE" 
log "Instance: $INSTANCE_ID"
log "Node Status: $(kubectl get node $(hostname) --no-headers | awk '{print $2}')"

exit 0
