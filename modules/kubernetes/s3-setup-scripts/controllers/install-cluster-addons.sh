#!/usr/bin/env bash
# =================================================================
# SHARED FUNCTIONS INTEGRATION
# =================================================================

# load shared functions
if [ -f "$$SCRIPT_DIR}/00-shared-functions.sh" ]; then
    source "$$SCRIPT_DIR}/00-shared-functions.sh"
    
    # Verify essential functions are available
    if command -v log_info >/dev/null 2>&1; then
        log_info "Shared functions loaded successfully"
    else
        echo "ERROR: Shared functions loaded but log_info not available"
        exit 1
    fi
else
    echo "ERROR: Cannot find shared functions file: $$SCRIPT_DIR}/00-shared-functions.sh"
    exit 1
fi

setup_logging "install-cluster-addons"

log_info "Starting K8s setup with log level: $$LOG_LEVEL}"

if [ -z "$SYSTEM_PREPARED" ] && [ ! -f "/tmp/.system_prepared" ]; then
    log_info "System not yet prepared, running preparation..."
    prepare_system_once
else
    log_info "System already prepared, skipping preparation"
fi


log_info "=== Terraform Remote-Exec Bootstrap ==="
log_info "Run started at: $(date)"

log_info "--- Running Apply Cluster Addons Script ---"
# Define wait parameters
WAIT_TIMEOUT=300 # 5 minutes timeout
WAIT_INTERVAL=10 # Check every 10 seconds

# Wait for API server again just to be sure before applying
log_info "Verifying API server readiness..."
ELAPSED=0

until sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes > /dev/null 2>&1; do
  if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then log_info "FATAL: Timeout waiting for API server before applying addons."; exit 1; fi
  sleep "$WAIT_INTERVAL"
  ELAPSED=$((ELAPSED + WAIT_INTERVAL))
  log_info "Waiting for API server ($$ELAPSED}s / $$WAIT_TIMEOUT}s)..."
done
log_info "API server ready. Applying addons..."

# Install metrics server
log_info "Installing metrics server..."
METRICS_URL="https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
curl -fsSL -o /tmp/metrics-components.yaml "$$METRICS_URL}" || { log_info "FATAL: Failed to download metrics-server manifests"; exit 1; }
# Optional patch if needed: sudo sed -i '/args:/a \        - --kubelet-insecure-tls' /tmp/metrics-components.yaml
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f /tmp/metrics-components.yaml || { log_info "FATAL: Failed to apply metrics-server manifests"; exit 1; }
log_info "Applied metrics-server manifests."

# Install AWS EBS CSI driver
# log_info "Installing AWS EBS CSI driver..."
# # Ensure kustomize is installed via user_data
# EBS_CSI_URL="https://github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=master"
# sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -k "$EBS_CSI_URL" || { log_info "FATAL: Failed to apply AWS EBS CSI driver using kustomize"; exit 1; }
# log_info "Applied AWS EBS CSI driver manifests."
#

log_info "Installing AWS EBS CSI driver..."
EBS_CSI_TAG="v1.29.0" # <-- Use specific stable tag
EBS_CSI_REPO="https://github.com/kubernetes-sigs/aws-ebs-csi-driver.git"
TMP_DIR="/tmp/aws-ebs-csi-driver"

# Clone the specific tag
rm -rf "$$TMP_DIR}" # Clean up previous attempt if any
git clone --depth 1 --branch "$$EBS_CSI_TAG}" "$$EBS_CSI_REPO}" "$$TMP_DIR}" || { log_info "FATAL: Failed to clone AWS EBS CSI driver repo"; exit 1; }

# Apply using the local Kustomize overlay path
KUSTOMIZE_PATH="$$TMP_DIR}/deploy/kubernetes/overlays/stable"
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -k "$$KUSTOMIZE_PATH}" || { log_info "FATAL: Failed to apply AWS EBS CSI driver using kustomize from local clone"; exit 1; }

# Clean up
rm -rf "$$TMP_DIR}"

log_info "Applied AWS EBS CSI driver manifests."


log_info "--- Apply Cluster Addons Script Finished ---"
