#!/bin/bash
# 04-install-cni.sh.tftpl
# Refactored to use shared functions architecture
# Installs and configures CNI plugin (Calico), sets up kubectl for target user, and finalizes cluster

# =================================================================
# SHARED FUNCTIONS INTEGRATION
# =================================================================
SCRIPT_DIR="$script_dir}"

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

setup_logging "install-cni"

log_info "Starting K8s setup with log level: $$LOG_LEVEL}"

if [ -z "$SYSTEM_PREPARED" ] && [ ! -f "/tmp/.system_prepared" ]; then
    log_info "System not yet prepared, running preparation..."
    prepare_system_once
else
    log_info "System already prepared, skipping preparation"
fi



# =================================================================
# CONFIGURATION VARIABLES (from Terraform)
# =================================================================
readonly TARGET_K8S_USER="$k8s_user}"
# Set CNI plugin with fallback
CNI_PLUGIN="$$cni_plugin}"
if [ -z "$CNI_PLUGIN" ]; then
    CNI_PLUGIN="calico"
fi
readonly CNI_PLUGIN

# Set CNI version with fallback  
CNI_VERSION="$$cni_version}"
if [ -z "$CNI_VERSION" ]; then
    CNI_VERSION="v3.27.0"
fi
readonly CNI_VERSION

readonly KUBECONFIG_PATH="/etc/kubernetes/admin.conf"
readonly COMPLETION_SIGNAL_FILE="/tmp/terraform_bootstrap_complete"

log_info "=== CNI Installation and Cluster Finalization Started ==="
log_info "Target User: $$TARGET_K8S_USER}"
log_info "CNI Plugin: $$CNI_PLUGIN}"
log_info "CNI Version: $$CNI_VERSION}"

# =================================================================
# CLUSTER VERIFICATION
# =================================================================
verify_cluster_accessibility() {
    log_info "=== Verifying Cluster Accessibility ==="
    
    # Check if admin config exists
    if [ ! -f "$$KUBECONFIG_PATH}" ]; then
        log_error "Kubernetes admin config not found: $$KUBECONFIG_PATH}"
        return 1
    fi
    
    # Set kubeconfig for this script
    export KUBECONFIG="$$KUBECONFIG_PATH}"
    
    # Test cluster connectivity
    log_info "Testing cluster connectivity..."
    local max_attempts=10
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if kubectl cluster-info >/dev/null 2>&1; then
            log_info "✅ Cluster is accessible"
            
            # Show cluster info for logging
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
# CNI PLUGIN INSTALLATION
# =================================================================
install_calico_cni() {
    log_info "=== Installing Calico CNI Plugin ==="
    
    local calico_url="https://raw.githubusercontent.com/projectcalico/calico/$$CNI_VERSION}/manifests/calico.yaml"
    
    log_info "Applying Calico manifests from: $$calico_url}"
    
    # Apply Calico manifests with retry
    local max_attempts=3
    for attempt in $(seq 1 $max_attempts); do
        log_info "Applying Calico manifests (attempt $attempt/$max_attempts)..."
        
        if kubectl apply -f "$$calico_url}"; then
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
    
    while [ $elapsed -lt $timeout ]; do
        log_info "Checking Calico pod status ($elapsed/$timeout seconds)..."
        
        # Show current pod status for debugging
        log_info "Calico node pods:"
        kubectl get pods -n kube-system -l k8s-app=calico-node -o wide 2>/dev/null | while IFS= read -r line; do
            log_info "  $line"
        done
        
        log_info "Calico controller pods:"
        kubectl get pods -n kube-system -l k8s-app=calico-kube-controllers -o wide 2>/dev/null | while IFS= read -r line; do
            log_info "  $line"
        done
        
        # Count ready pods
        local calico_nodes_ready=0
        local calico_controllers_ready=0
        
        calico_nodes_ready=$(kubectl get pods -n kube-system -l k8s-app=calico-node \
                              --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        calico_controllers_ready=$(kubectl get pods -n kube-system -l k8s-app=calico-kube-controllers \
                                    --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        
        log_info "Ready pods - Nodes: $calico_nodes_ready, Controllers: $calico_controllers_ready"
        
        # Check if we have at least one of each type running
        if [ "$calico_nodes_ready" -gt 0 ] && [ "$calico_controllers_ready" -gt 0 ]; then
            log_info "✅ Calico pods are ready"
            break
        fi
        
        if [ $elapsed -ge $timeout ]; then
            log_error "Timeout waiting for Calico pods to be ready"
            log_error "Current pod status:"
            kubectl get pods -n kube-system -l k8s-app=calico-node || true
            kubectl get pods -n kube-system -l k8s-app=calico-kube-controllers || true
            return 1
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    return 0
}

install_flannel_cni() {
    log_info "=== Installing Flannel CNI Plugin ==="
    
    local flannel_url="https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"
    
    log_info "Applying Flannel manifests from: $$flannel_url}"
    
    if kubectl apply -f "$$flannel_url}"; then
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

install_cni_plugin() {
    log_info "=== Installing CNI Plugin: $$CNI_PLUGIN} ==="
    
    case "$$CNI_PLUGIN}" in
        "calico")
            install_calico_cni && wait_for_calico_pods
            ;;
        "flannel")
            install_flannel_cni
            ;;
        *)
            log_error "Unsupported CNI plugin: $$CNI_PLUGIN}"
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
    
    log_info "Waiting for all nodes to be ready..."
    if kubectl wait --for=condition=Ready nodes --all --timeout=300s; then
        log_info "✅ All nodes are ready"
        
        # Show final node status
        log_info "Final node status:"
        kubectl get nodes -o wide | while IFS= read -r line; do
            log_info "  $line"
        done
    else
        log_error "Timeout waiting for nodes to be ready"
        log_error "Current node status:"
        kubectl get nodes -o wide || true
        return 1
    fi
    
    return 0
}

# =================================================================
# USER KUBECTL CONFIGURATION
# =================================================================
setup_user_kubectl_config() {
    log_info "=== Setting up kubectl Configuration for User ==="
    
    log_info "Configuring kubectl for user: $$TARGET_K8S_USER}"
    
    # Verify user exists
    if ! id "$$TARGET_K8S_USER}" &>/dev/null; then
        log_warn "User $$TARGET_K8S_USER} does not exist, skipping kubectl setup"
        return 0
    fi
    
    log_info "✅ User $$TARGET_K8S_USER} exists"
    
    # Get user information
    local target_uid=""
    local target_gid=""
    
    if ! target_uid=$(id -u "$$TARGET_K8S_USER}" 2>/dev/null); then
        log_error "Failed to get UID for user $$TARGET_K8S_USER}"
        return 1
    fi
    
    if ! target_gid=$(id -g "$$TARGET_K8S_USER}" 2>/dev/null); then
        log_error "Failed to get GID for user $$TARGET_K8S_USER}"
        return 1
    fi
    
    # Set up kubectl config
    local kube_dir="/home/$$TARGET_K8S_USER}/.kube"
    local kube_config="$$kube_dir}/config"
    
    log_info "Creating kubectl directory: $$kube_dir}"
    mkdir -p "$$kube_dir}"
    
    log_info "Copying admin config to user config..."
    if [ ! -f "$$KUBECONFIG_PATH}" ]; then
        log_error "Admin config not found: $$KUBECONFIG_PATH}"
        return 1
    fi
    
    cp "$$KUBECONFIG_PATH}" "$$kube_config}"
    
    # Set proper ownership
    log_info "Setting ownership to $target_uid:$target_gid"
    chown "$target_uid:$target_gid" "$$kube_dir}"
    chown "$target_uid:$target_gid" "$$kube_config}"
    
    # Set proper permissions
    chmod 700 "$$kube_dir}"
    chmod 600 "$$kube_config}"
    
    log_info "✅ kubectl configured successfully for user $$TARGET_K8S_USER}"
    
    # Test the configuration as the user
    log_info "Testing kubectl access for user $$TARGET_K8S_USER}..."
    if sudo -u "$$TARGET_K8S_USER}" kubectl get nodes >/dev/null 2>&1; then
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
    touch "$$COMPLETION_SIGNAL_FILE}"
    chmod 644 "$$COMPLETION_SIGNAL_FILE}"
    
    # Add metadata to the signal file
    cat > "$$COMPLETION_SIGNAL_FILE}" << EOF
# Terraform Bootstrap Completion Signal
# Generated at: $(date)
# User: $(whoami)
# CNI Plugin: $$CNI_PLUGIN}
# Target User: $$TARGET_K8S_USER}
# Cluster Status: Ready
EOF
    
    log_info "✅ Completion signal created: $$COMPLETION_SIGNAL_FILE}"
}

perform_final_verification() {
    log_info "=== Final Cluster Verification ==="
    
    # Final cluster state verification
    log_info "Final cluster information:"
    kubectl cluster-info | while IFS= read -r line; do
        log_info "  $line"
    done
    
    log_info "All nodes:"
    kubectl get nodes -o wide | while IFS= read -r line; do
        log_info "  $line"
    done
    
    log_info "All pods across all namespaces:"
    kubectl get pods -A -o wide | while IFS= read -r line; do
        log_info "  $line"
    done
    
    log_info "System services status:"
    kubectl get svc -A | while IFS= read -r line; do
        log_info "  $line"
    done
    
    # Check cluster health
    log_info "Cluster component status:"
    kubectl get componentstatuses 2>/dev/null | while IFS= read -r line; do
        log_info "  $line"
    done || log_warn "Component status check not available"
    
    log_info "✅ Final verification completed"
}

# =================================================================
# MAIN EXECUTION
# =================================================================
main() {
    log_info "Starting CNI installation and cluster finalization..."
    
    # Verify cluster is accessible
    if ! verify_cluster_accessibility; then
        log_error "Cluster accessibility verification failed"
        return 1
    fi
    
    # Install CNI plugin
    if ! install_cni_plugin; then
        log_error "CNI plugin installation failed"
        return 1
    fi
    
    # Wait for nodes to be ready
    if ! wait_for_nodes_ready; then
        log_error "Nodes failed to become ready"
        return 1
    fi
    
    # Set up kubectl for target user
    if ! setup_user_kubectl_config; then
        log_error "Failed to set up kubectl configuration for user"
        return 1
    fi
    
    # Create completion signal
    create_completion_signal
    
    # Final verification
    perform_final_verification
    
    log_info "=== CNI Installation and Cluster Finalization Completed Successfully ==="
    log_info "✅ CNI Plugin ($$CNI_PLUGIN}) installed and ready"
    log_info "✅ All nodes are ready"
    log_info "✅ kubectl configured for user: $$TARGET_K8S_USER}"
    log_info "✅ Completion signal created: $$COMPLETION_SIGNAL_FILE}"
    log_info "✅ Cluster is fully operational"
    
    return 0
}

# Execute main function
main "$@"
