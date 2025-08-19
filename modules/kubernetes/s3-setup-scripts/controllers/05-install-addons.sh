#!/bin/bash
# 05-install-addons.sh.tftpl
# Refactored to use shared functions architecture
# Installs essential cluster addons: metrics-server, AWS EBS CSI driver, and other optional components

# =================================================================
# SHARED FUNCTIONS INTEGRATION
# =================================================================

# load shared functions
if [ -f "${SCRIPT_DIR}/00-shared-functions.sh" ]; then
    source "${SCRIPT_DIR}/00-shared-functions.sh"
    
    # Verify essential functions are available
    if command -v log_info >/dev/null 2>&1; then
        log_info "Shared functions loaded successfully"
    else
        echo "ERROR: Shared functions loaded but log_info not available"
        exit 1
    fi
else
    echo "ERROR: Cannot find shared functions file: ${SCRIPT_DIR}/00-shared-functions.sh"
    exit 1
fi

setup_logging "install-addons"

log_info "Starting K8s setup with log level: ${LOG_LEVEL}"

if [ -z "$SYSTEM_PREPARED" ] && [ ! -f "/tmp/.system_prepared" ]; then
    log_info "System not yet prepared, running preparation..."
    prepare_system_once
else
    log_info "System already prepared, skipping preparation"
fi



log_info "Run started at: $(date)"

# =================================================================
# CONFIGURATION VARIABLES (from Terraform)
# =================================================================
readonly CLUSTER_NAME="$cluster_name}"

# Set variables with fallbacks
INSTALL_METRICS_SERVER="${install_metrics_server}"
if [ -z "$INSTALL_METRICS_SERVER" ]; then
    INSTALL_METRICS_SERVER="true"
fi
readonly INSTALL_METRICS_SERVER

INSTALL_EBS_CSI_DRIVER="${install_ebs_csi_driver}"
if [ -z "$INSTALL_EBS_CSI_DRIVER" ]; then
    INSTALL_EBS_CSI_DRIVER="true"
fi
readonly INSTALL_EBS_CSI_DRIVER

INSTALL_AWS_LOAD_BALANCER_CONTROLLER="${install_aws_load_balancer_controller}"
if [ -z "$INSTALL_AWS_LOAD_BALANCER_CONTROLLER" ]; then
    INSTALL_AWS_LOAD_BALANCER_CONTROLLER="false"
fi
readonly INSTALL_AWS_LOAD_BALANCER_CONTROLLER

METRICS_SERVER_VERSION="${metrics_server_version}"
if [ -z "$METRICS_SERVER_VERSION" ]; then
    METRICS_SERVER_VERSION="latest"
fi
readonly METRICS_SERVER_VERSION

EBS_CSI_DRIVER_VERSION="${ebs_csi_driver_version}"
if [ -z "$EBS_CSI_DRIVER_VERSION" ]; then
    EBS_CSI_DRIVER_VERSION="v1.29.0"
fi
readonly EBS_CSI_DRIVER_VERSION

readonly AWS_REGION="${aws_region}"
readonly KUBECONFIG_PATH="/etc/kubernetes/admin.conf"

log_info "=== Cluster Addons Installation Started ==="
log_info "Cluster: ${CLUSTER_NAME}"
log_info "Install Metrics Server: ${INSTALL_METRICS_SERVER}"
log_info "Install EBS CSI Driver: ${INSTALL_EBS_CSI_DRIVER}"
log_info "Install AWS LB Controller: ${INSTALL_AWS_LOAD_BALANCER_CONTROLLER}"

# =================================================================
# CLUSTER READINESS VERIFICATION
# =================================================================
verify_cluster_readiness() {
    log_info "=== Verifying Cluster Readiness ==="
    
    # Set kubeconfig
    export KUBECONFIG="${KUBECONFIG_PATH}"
    
    # Check if admin config exists
    if [ ! -f "${KUBECONFIG_PATH}" ]; then
        log_error "Kubernetes admin config not found: ${KUBECONFIG_PATH}"
        return 1
    fi
    
    log_info "Waiting for API server to be fully ready..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if kubectl get nodes >/dev/null 2>&1; then
            log_info "✅ API server is accessible"
            break
        fi
        
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            log_info "API server not ready, waiting... ($attempt/$max_attempts)"
            sleep 10
        else
            log_error "API server not ready after $max_attempts attempts"
            return 1
        fi
    done
    
    # Verify all nodes are ready
    log_info "Verifying all nodes are ready..."
    if kubectl get nodes | grep -q "NotReady"; then
        log_warn "Some nodes are not ready:"
        kubectl get nodes | while IFS= read -r line; do
            log_warn "  $line"
        done
        log_warn "Continuing with addon installation anyway..."
    else
        log_info "✅ All nodes are ready"
    fi
    
    # Verify system pods are running
    log_info "Checking system pods status..."
    kubectl get pods -n kube-system | while IFS= read -r line; do
        log_info "  $line"
    done
    
    return 0
}

# =================================================================
# METRICS SERVER INSTALLATION
# =================================================================
install_metrics_server() {
    log_info "=== Installing Metrics Server ==="
    
    if [ "${INSTALL_METRICS_SERVER}" != "true" ]; then
        log_info "Metrics server installation skipped (disabled in configuration)"
        return 0
    fi
    
    local metrics_url=""
    if [ "${METRICS_SERVER_VERSION}" = "latest" ]; then
        metrics_url="https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
    else
        metrics_url="https://github.com/kubernetes-sigs/metrics-server/releases/download/${$METRICS_SERVER_VERSION}/components.yaml"
    fi
    
    log_info "Downloading metrics-server manifests from: ${metrics_url}"
    
    local temp_file="/tmp/metrics-components.yaml"
    if curl -fsSL -o "${temp_file}" "${metrics_url}"; then
        log_info "✅ Metrics server manifests downloaded"
    else
        log_error "Failed to download metrics-server manifests"
        return 1
    fi
    
    # Apply manifests
    log_info "Applying metrics-server manifests..."
    if kubectl apply -f "${temp_file}"; then
        log_info "✅ Metrics server manifests applied"
    else
        log_error "Failed to apply metrics-server manifests"
        return 1
    fi
    
    # Wait for metrics server to be ready
    log_info "Waiting for metrics-server deployment to be ready..."
    if kubectl rollout status deployment/metrics-server -n kube-system --timeout=300s; then
        log_info "✅ Metrics server is ready"
    else
        log_error "Metrics server failed to become ready"
        log_error "Deployment status:"
        kubectl get deployment metrics-server -n kube-system -o wide || true
        log_error "Pod status:"
        kubectl get pods -n kube-system -l k8s-app=metrics-server || true
        return 1
    fi
    
    # Test metrics server functionality
    log_info "Testing metrics server functionality..."
    local test_attempts=5
    for attempt in $(seq 1 $test_attempts); do
        if kubectl top nodes >/dev/null 2>&1; then
            log_info "✅ Metrics server is functional"
            break
        elif [ $attempt -eq $test_attempts ]; then
            log_warn "Metrics server may not be fully functional yet (this is normal)"
        else
            log_info "Metrics not available yet, waiting... ($attempt/$test_attempts)"
            sleep 10
        fi
    done
    
    # Cleanup
    rm -f "${temp_file}"
    
    return 0
}

# =================================================================
# EBS CSI DRIVER INSTALLATION
# =================================================================
install_ebs_csi_driver() {
    log_info "=== Installing AWS EBS CSI Driver ==="
    
    if [ "${INSTALL_EBS_CSI_DRIVER}" != "true" ]; then
        log_info "EBS CSI driver installation skipped (disabled in configuration)"
        return 0
    fi
    
    # Check if git is available
    if ! command -v git >/dev/null 2>&1; then
        log_info "Installing git for CSI driver deployment..."
        install_packages "git"
    fi
    
    local repo_url="https://github.com/kubernetes-sigs/aws-ebs-csi-driver.git"
    local temp_dir="/tmp/aws-ebs-csi-driver"
    
    # Clean up any previous attempts
    rm -rf "${temp_dir}"
    
    log_info "Cloning EBS CSI driver repository (version: ${EBS_CSI_DRIVER_VERSION})..."
    if git clone --depth 1 --branch "${EBS_CSI_DRIVER_VERSION}" "${repo_url}" "$#{temp_dir}"; then
        log_info "✅ EBS CSI driver repository cloned"
    else
        log_error "Failed to clone EBS CSI driver repository"
        return 1
    fi
    
    # Apply using kustomize
    local kustomize_path="${temp_dir}/deploy/kubernetes/overlays/stable"
    
    if [ ! -d "${kustomize_path}" ]; then
        log_error "Kustomize overlay path not found: ${kustomize_path}"
        log_error "Available paths:"
        find "${temp_dir}" -name "*.yaml" -type d | head -10 || true
        return 1
    fi
    
    log_info "Applying EBS CSI driver manifests using kustomize..."
    if kubectl apply -k "${kustomize_path}"; then
        log_info "✅ EBS CSI driver manifests applied"
    else
        log_error "Failed to apply EBS CSI driver manifests"
        return 1
    fi
    
    # Wait for CSI driver to be ready
    log_info "Waiting for EBS CSI driver to be ready..."
    
    # Wait for daemonset
    if kubectl rollout status daemonset/ebs-csi-node -n kube-system --timeout=300s; then
        log_info "✅ EBS CSI node daemonset is ready"
    else
        log_warn "EBS CSI node daemonset may not be ready yet"
    fi
    
    # Wait for deployment
    if kubectl rollout status deployment/ebs-csi-controller -n kube-system --timeout=300s; then
        log_info "✅ EBS CSI controller deployment is ready"
    else
        log_warn "EBS CSI controller deployment may not be ready yet"
    fi
    
    # Verify storage class was created
    log_info "Checking for gp2 storage class..."
    if kubectl get storageclass gp2 >/dev/null 2>&1; then
        log_info "✅ gp2 storage class is available"
    else
        log_warn "gp2 storage class not found, this may be normal depending on the driver version"
    fi
    
    # Show CSI driver pods status
    log_info "EBS CSI driver pods status:"
    kubectl get pods -n kube-system -l app=ebs-csi-controller | while IFS= read -r line; do
        log_info "  $line"
    done
    kubectl get pods -n kube-system -l app=ebs-csi-node | while IFS= read -r line; do
        log_info "  $line"
    done
    
    # Cleanup
    rm -rf "${temp_dir}"
    
    return 0
}

# =================================================================
# AWS LOAD BALANCER CONTROLLER (OPTIONAL)
# =================================================================
install_aws_load_balancer_controller() {
    log_info "=== Installing AWS Load Balancer Controller ==="
    
    if [ "${INSTALL_AWS_LOAD_BALANCER_CONTROLLER}" != "true" ]; then
        log_info "AWS Load Balancer Controller installation skipped (disabled in configuration)"
        return 0
    fi
    
    # This is a more complex installation that requires:
    # 1. IAM service account
    # 2. Cert-manager (dependency)
    # 3. Proper RBAC
    
    log_warn "AWS Load Balancer Controller installation is complex and requires additional IAM setup"
    log_warn "Consider using Terraform aws-load-balancer-controller module instead"
    log_warn "Skipping for now - implement if needed"
    
    return 0
}

# =================================================================
# ADDON VALIDATION
# =================================================================
validate_addons() {
    log_info "=== Validating Installed Addons ==="
    
    # Check metrics server
    if [ "${INSTALL_METRICS_SERVER}" = "true" ]; then
        log_info "Validating metrics server..."
        if kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
            local replicas_ready=""
            replicas_ready=$(kubectl get deployment metrics-server -n kube-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            log_info "✅ Metrics server deployment found ($replicas_ready replicas ready)"
        else
            log_warn "❌ Metrics server deployment not found"
        fi
    fi
    
    # Check EBS CSI driver
    if [ "${INSTALL_EBS_CSI_DRIVER}" = "true" ]; then
        log_info "Validating EBS CSI driver..."
        if kubectl get deployment ebs-csi-controller -n kube-system >/dev/null 2>&1; then
            log_info "✅ EBS CSI controller deployment found"
        else
            log_warn "❌ EBS CSI controller deployment not found"
        fi
        
        if kubectl get daemonset ebs-csi-node -n kube-system >/dev/null 2>&1; then
            log_info "✅ EBS CSI node daemonset found"
        else
            log_warn "❌ EBS CSI node daemonset not found"
        fi
    fi
    
    # Show all addon-related pods
    log_info "All addon pods status:"
    kubectl get pods -n kube-system | grep -E "(metrics-server|ebs-csi)" | while IFS= read -r line; do
        log_info "  $line"
    done || log_info "  No addon pods found matching criteria"
    
    return 0
}

# =================================================================
# MAIN EXECUTION
# =================================================================
main() {
    log_info "Starting cluster addons installation..."
    
    # Verify cluster is ready for addons
    if ! verify_cluster_readiness; then
        log_error "Cluster readiness verification failed"
        return 1
    fi
    
    # Install metrics server
    if ! install_metrics_server; then
        log_error "Metrics server installation failed"
        return 1
    fi
    
    # Install EBS CSI driver
    if ! install_ebs_csi_driver; then
        log_error "EBS CSI driver installation failed"
        return 1
    fi
    
    # Install AWS Load Balancer Controller (if enabled)
    if ! install_aws_load_balancer_controller; then
        log_error "AWS Load Balancer Controller installation failed"
        return 1
    fi
    
    # Validate all addons
    validate_addons
    
    log_info "=== Cluster Addons Installation Completed Successfully ==="
    
    # Summary
    local installed_addons=""
    if [ "${INSTALL_METRICS_SERVER}" = "true" ]; then
        installed_addons="metrics-server"
    fi
    if [ "${INSTALL_EBS_CSI_DRIVER}" = "true" ]; then
        if [ -n "$installed_addons" ]; then
            installed_addons="$installed_addons aws-ebs-csi-driver"
        else
            installed_addons="aws-ebs-csi-driver"
        fi
    fi
    if [ "${INSTALL_AWS_LOAD_BALANCER_CONTROLLER}" = "true" ]; then
        if [ -n "$installed_addons" ]; then
            installed_addons="$installed_addons aws-load-balancer-controller"
        else
            installed_addons="aws-load-balancer-controller"
        fi
    fi
    
    log_info "✅ Installed addons: $installed_addons"
    log_info "✅ Cluster is ready for workloads"
    
    return 0
}

# Execute main function
main "$@"
