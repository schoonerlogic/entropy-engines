#!/bin/bash
# 04-install-cni.sh.tftpl
# Refactored to use shared functions architecture
# Installs and configures CNI plugin (Calico), sets up kubectl for target user, and finalizes cluster

set -euo pipefail
IFS=$'\n\t'

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

setup_logging "install-cni"

log_info "Starting K8s setup with log level: ${LOG_LEVEL}"

if [ -z "${SYSTEM_PREPARED}" ] && [ ! -f "/tmp/.system_prepared" ]; then
    log_info "System not yet prepared, running preparation..."
    prepare_system_once
else
    log_info "System already prepared, skipping preparation"
fi


# =================================================================
# CONFIGURATION VARIABLES (from Terraform)
# =================================================================
readonly KUBECONFIG_PATH="/etc/kubernetes/admin.conf"
readonly COMPLETION_SIGNAL_FILE="/tmp/terraform_bootstrap_complete"

log_info "=== CNI Installation and Cluster Finalization Started ==="
log_info "Target User: ${K8S_USER}"
log_info "CNI Plugin: ${CNI_PLUGIN}"
log_info "CNI Version: ${CNI_VERSION}"

# =================================================================
# CLUSTER VERIFICATION
# =================================================================
verify_cluster_accessibility() {
    log_info "=== Verifying Cluster Accessibility ==="
    
    # Check if admin config exists
    if [ ! -f "${KUBECONFIG_PATH}" ]; then
        log_error "Kubernetes admin config not found: ${KUBECONFIG_PATH}"
        return 1
    fi
    
    # Set kubeconfig for this script
    export KUBECONFIG="${KUBECONFIG_PATH}"
    
    # Test cluster connectivity
    log_info "Testing cluster connectivity..."
    local max_attempts=10
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if kubectl cluster-info >/dev/null 2>&1; then
            log_info "✅ Cluster is accessible"
            
            # Show cluster info for logging
            aws_region     = ${INSTANCE_REGION}
            log_info "Cluster information:"
            kubectl cluster-info | while IFS= read -r line; do
                log_info "  $line"
            done
            return 0
        fi
        
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            log_warn "Cluster not accessible yet, retrying ($attempt/$max_attempts)..."
            sleep 10
        fi
    done
    
    log_error "Cluster is not accessible after $max_attempts attempts"
    return 1
}

# =================================================================
# CALICO CNI PLUGIN INSTALLATION
# =================================================================
install_calico_cni() {
    log_info "=== Installing Calico CNI Plugin ==="
    
    local calico_url="https://raw.githubusercontent.com/projectcalico/calico/${CNI_VERSION}/manifests/calico.yaml"
    
    log_info "Applying Calico manifests from: ${calico_url}"
    
    # Apply Calico manifests with retry
    local max_attempts=3
    for attempt in $(seq 1 $max_attempts); do
        log_info "Applying Calico manifests (attempt $attempt/$max_attempts)..."
        
        if kubectl apply -f "${calico_url}"; then
            log_info "✅ Calico manifests applied successfully"
            break
        elif [ $attempt -eq $max_attempts ]; then
            log_error "Failed to apply Calico manifests after $max_attempts attempts"
            return 1
        else
            log_warn "Failed to apply Calico manifests, retrying..."
            sleep 10
        fi
    done
    
    return 0
}

wait_for_calico_pods() {
    log_info "=== Waiting for Calico Pods to be Ready ==="
    
    local timeout=300  # 5 minutes
    local interval=10
    local elapsed=0
    
    log_info "Waiting for Calico DaemonSet & Deployment …"
    kubectl -n kube-system rollout status ds/calico-node     --timeout=300s
    kubectl -n kube-system rollout status deploy/calico-kube-controllers --timeout=300s
}

# =================================================================
# FLANNEL CNI PLUGIN INSTALLATION
# =================================================================
install_flannel_cni() {
    log_info "=== Installing Flannel CNI Plugin ==="
    
    local flannel_url="https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"
    
    log_info "Applying Flannel manifests from: ${flannel_url}"
    
    if kubectl apply -f "${flannel_url}"; then
        log_info "✅ Flannel manifests applied successfully"
        
        # Wait for flannel pods
        log_info "Waiting for Flannel pods to be ready..."
        kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s || {
            log_error "Flannel rollout failed or timed out"
            return 1
        }
        
        log_info "✅ Flannel is ready"
    else
        log_error "Failed to apply Flannel manifests"
        return 1
    fi
    
    return 0
}

wait_for_flannel_pods() {
    log_info "=== Waiting for flannes Pods to be Ready ==="
    
    local timeout=300  # 5 minutes
    local interval=10
    local elapsed=0
    
    log_info "Waiting for Flannel DaemonSet & Deployment …"
    kubectl -n kube-system rollout status ds/flannel-node     --timeout=300s
    kubectl -n kube-system rollout status deploy/flannel-kube-controllers --timeout=300s
}


# =================================================================
#  CNI PLUGIN INVOKE INSTALLATION
# =================================================================
install_cni_plugin() {
    log_info "=== Installing CNI Plugin: ${CNI_PLUGIN} ==="
    
    case "${CNI_PLUGIN}" in
        "calico")
            install_calico_cni && wait_for_calico_pods
            ;;
        "flannel")
            install_flannel_cni
            ;;
        *)
            log_error "Unsupported CNI plugin: ${CNI_PLUGIN}"
            return 1
            ;;
    esac
    
    return $?
}

# =================================================================
# NODE READINESS
# =================================================================
wait_for_nodes_ready() {
    log_info "=== Waiting for Nodes to be Ready ==="
    
    kubectl wait --for=condition=Ready nodes --all --timeout=300s
}

# =================================================================
# USER KUBECTL CONFIGURATION
# =================================================================
setup_user_kubectl_config() {
    log_info "=== Setting up kubectl Configuration for User ==="
    
    log_info "Configuring kubectl for user: ${K8S_USER}"
    
    # Verify user exists
    if ! id "${K8S_USER}" &>/dev/null; then
        log_warn "User ${K8S_USER} does not exist, skipping kubectl setup"
        return 0
    fi
    
    log_info "✅ User ${K8S_USER} exists"
    
    # Get user information
    local target_uid=""
    local target_gid=""
    
    if ! target_uid=$(id -u "${K8S_USER}" 2>/dev/null); then
        log_error "Failed to get UID for user ${K8S_USER}"
        return 1
    fi
    
    if ! target_gid=$(id -g "${K8S_USER}" 2>/dev/null); then
        log_error "Failed to get GID for user ${K8S_USER}"
        return 1
    fi
    
    # Set up kubectl config
    local kube_dir="/home/${K8S_USER}/.kube"
    local kube_config="${kube_dir}/config"
    
    log_info "Creating kubectl directory: ${kube_dir}"
    mkdir -p "${kube_dir}"
    
    log_info "Copying admin config to user config..."
    if [ ! -f "${KUBECONFIG_PATH}" ]; then
        log_error "Admin config not found: ${KUBECONFIG_PATH}"
        return 1
    fi
    
    # Set proper ownership
    log_info "Setting ownership to $target_uid:$target_gid"
    chown "$target_uid:$target_gid" "${kube_dir}"
    chown "$target_uid:$target_gid" "${kube_config}"
    
    # Set proper permissions
    chmod 700 "${kube_dir}"
    chmod 600 "${kube_config}"
    
    log_info "✅ kubectl configured successfully for user ${K8S_USER}"
    
    # Test the configuration as the user
    log_info "Testing kubectl access for user ${K8S_USER}..."
    if sudo -u "${K8S_USER}" kubectl get nodes >/dev/null 2>&1; then
        log_info "✅ User can successfully access cluster with kubectl"
    else
        log_warn "User may not be able to access cluster (this could be normal if CNI is still starting)"
    fi
    
    return 0
}

# =================================================================
# CLUSTER FINALIZATION
# =================================================================
create_completion_signal() {
    log_info "=== Creating Completion Signal ==="
    
    # Create completion signal file
    touch "${COMPLETION_SIGNAL_FILE}"
    chmod 644 "${COMPLETION_SIGNAL_FILE}"
    
    # Add metadata to the signal file
    cat > "${COMPLETION_SIGNAL_FILE}" << EOF
# Terraform Bootstrap Completion Signal
# Generated at: $(date)
# User: $(whoami)
# CNI Plugin: ${CNI_PLUGIN}
# Target User: ${K8S_USER}
# Cluster Status: Ready
EOF
    
    log_info "✅ Completion signal created: ${COMPLETION_SIGNAL_FILE}"
}


################################################################################
# Atomic kubeconfig swap (idempotent, temp-file + mv)
################################################################################
update_kubeconfig_for_dns() {
    local target_dns_name=$1
    local kubeconfig=${2:-/etc/kubernetes/admin.conf}

    [[ -f $kubeconfig ]] || { log_warn "kubeconfig missing, skipping"; return 0; }

    local tmp
    tmp=$(mktemp /tmp/kubeconfig.XXXXXX)
    trap 'rm -f "$tmp"' EXIT         # always clean up

    cp "$kubeconfig" "$tmp"
    kubectl config set-cluster "$(kubectl config current-cluster --kubeconfig="$tmp")" \
        --server="https://${target_dns_name}:6443" \
        --kubeconfig="$tmp" >/dev/null

    mv "$tmp" "$kubeconfig"          # atomic
    chown root:root "$kubeconfig"
    chmod 600 "$kubeconfig"
    log_info "✅ kubeconfig updated to https://${target_dns_name}:6443"
}

################################################################################
# Simple POSIX file lock around the whole bootstrap
################################################################################
with_lock() {
    local lockfile="/var/lock/$(basename "$0").lock"
    exec 9>"$lockfile"
    flock -n 9 || { log_error "Another instance is already running"; return 1; }
    log_info "Acquired bootstrap lock $lockfile"
}

################################################################################
# Main Execution
################################################################################
main() {
    with_lock || return 1   # prevent concurrent runs

    log_info "=== CNI Installation & Cluster Finalization ==="

    # 1.  Basic sanity
    verify_cluster_accessibility || return 1

    # 2.  CNI
    install_cni_plugin || return 1
    wait_for_nodes_ready || return 1

    # 3.  User kubectl
    setup_user_kubectl_config || return 1

    # 4.  Decide which DNS record to use
    local api_dns_name
    if [[ ${USE_ROUTE53:-false} == "true" ]]; then
        api_dns_name="${API_DNS_NAME}"
    else
        api_dns_name="${nlb_dns_name}"
    fi

    # 5.  Update kubeconfig to point at the load-balancer
    update_kubeconfig_for_dns "$api_dns_name" "${KUBECONFIG_PATH}"

    # 6.  Final verification (must succeed for CI)
    verify_load_balancer_setup || return 1

    # 7.  Completion signal
    create_completion_signal

    # 8.  Machine-friendly summary
    jq -n \
        --arg cni      "${CNI_PLUGIN}" \
        --arg user     "${K8S_USER}" \
        --arg endpoint "https://${api_dns_name}:${API_PORT}" \
        --arg signal   "${COMPLETION_SIGNAL_FILE}" \
        '{status:"success",cni:$cni,user:$user,api_endpoint:$endpoint,signal_file:$signal}'

    log_info "=== Bootstrap complete ==="
}

# Execute main function
main "$@"
