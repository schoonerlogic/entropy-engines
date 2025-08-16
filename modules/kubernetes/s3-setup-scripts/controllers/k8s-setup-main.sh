#!/bin/bash
# /tmp/k8s_scripts/k8s-setup-main.sh
# Main wrapper script that orchestrates all K8s setup scripts

echo "=== Kubernetes Setup Started at $(date) ==="

# =================================================================
# SHARED FUNCTIONS INTEGRATION  
# =================================================================
SCRIPT_DIR="$script_dir}"

# Set DEBUG default to avoid unbound variable errors
DEBUG=0

echo "DEBUG: script_dir resolved to: $script_dir}"

# Load shared functions
if [ -f "$$SCRIPT_DIR}/00-shared-functions.sh" ]; then
    source "$$SCRIPT_DIR}/00-shared-functions.sh"
    
    # Explicitly setup logging with this script's name
    setup_logging "k8s-setup-main"
    
    # Verify essential functions are available
    if command -v log_info >/dev/null 2>&1; then
        log_info "Shared functions loaded successfully"
    else
        echo "ERROR: Shared functions loaded but log_info not available"
        exit 1
    fi
else
    echo "ERROR: Cannot find shared functions file: $$SCRIPT_DIR}/00-shared-functions.sh"
    echo "Current directory contents:"
    ls -la "$$SCRIPT_DIR}/" || echo "Directory does not exist"
    exit 1
fi

# Log that we're starting (log level is handled by shared functions)
log_info "Starting K8s setup"

# System preparation (let shared functions handle the logic)
log_info "Checking system preparation status..."
if command -v prepare_system_once >/dev/null 2>&1; then
    prepare_system_once
else
    log_error "prepare_system_once function not available"
    exit 1
fi

# Define the scripts to run in order
SCRIPTS=(
    "01-install-user-and-tooling.sh"
    "02-install-kubernetes.sh" 
    "03-configure-cluster.sh"
    "04-install-cni.sh"
    "05-install-cluster-addons.sh"
)

# Execute scripts in sequence
for script in "$$SCRIPTS[@]}"; do
    script_path="$$SCRIPT_DIR}/$script"
    
    if [ -f "$script_path" ]; then
        log_info "Starting script: $script"
        
        # Export environment for sub-scripts  
        export SCRIPT_EXECUTION_MODE="normal"
        export SYSTEM_PREPARED="true"
        
        if bash "$script_path"; then
            log_info "Script completed successfully: $script"
        else
            exit_code=$?
            log_error "Script failed: $script (exit code: $exit_code)"
            exit $exit_code
        fi
    else
        log_warn "Script not found, skipping: $script_path"
    fi
done

log_info "=== Kubernetes Setup Completed Successfully at $(date) ==="

# Final log message with fallback
if [ -n "$MAIN_LOG_PATH" ]; then
    echo "Setup completed. Check $MAIN_LOG_PATH for full details."
else
    echo "Setup completed. Check /var/log/provisioning/k8s-setup-main.log for full details."
fi
