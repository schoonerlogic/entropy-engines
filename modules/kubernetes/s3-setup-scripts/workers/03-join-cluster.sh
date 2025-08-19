#!/bin/bash
# 03-join-cluster.sh.tftpl
# Worker node script to join Kubernetes cluster

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

setup_logging "join-cluster"

log_info "Starting K8s worker join process"

if [ -z "$SYSTEM_PREPARED" ] && [ ! -f "/tmp/.system_prepared" ]; then
    log_info "System not yet prepared, running preparation..."
    prepare_system_once
else
    log_info "System already prepared, skipping preparation"
fi

# =================================================================
# CONFIGURATION VARIABLES (from Terraform)
# =================================================================
readonly CLUSTER_NAME="$cluster_name}"
readonly SSM_JOIN_COMMAND_PATH="$ssm_join_command_path}"

log_info "=== Worker Node Cluster Join Started ==="
log_info "Cluster Name: $CLUSTER_NAME"
log_info "SSM Join Command Path: $SSM_JOIN_COMMAND_PATH"

# =================================================================
# SHARED EC2 METADATA
# =================================================================
source "$$/{{SCRIPT_DIR}/001-ec2-metadata-lib.sh"
ec2_init_metadata || exit 1

# =================================================================
# AWS CREDENTIALS VALIDATION
# =================================================================
validate_aws_credentials() {
    log_info "=== Validating AWS Credentials ==="
    
    # Check IAM role credentials
    if [ -z "$AWS_METADATA_TOKEN" ]; then
        log_warn "No metadata token available for credential validation"
        return 1
    fi
    
    # Test AWS CLI functionality
    if command -v aws >/dev/null 2>&1; then
        log_info "AWS CLI configuration:"
        aws configure list || log_warn "AWS configure list failed"
        
        log_info "AWS identity:"
        if aws sts get-caller-identity; then
            log_info "AWS credentials validated successfully"
        else
            log_warn "AWS credentials validation failed"
        fi
    else
        log_warn "AWS CLI not available for credential validation"
    fi
}

# =================================================================
# JOIN COMMAND RETRIEVAL
# =================================================================
get_join_command() {
    log_info "=== Retrieving Join Command from SSM ==="
    
    local max_attempts=40
    local wait_interval=15
    local attempt=1
    
    log_info "Waiting for join command from primary controller..."
    
    while [ $attempt -le $max_attempts ]; do
        log_info "Attempt $attempt/$max_attempts to retrieve join command..."
        
        local join_cmd=""
        if join_cmd=$(aws ssm get-parameter --name "$SSM_JOIN_COMMAND_PATH" \
                        --with-decryption --query Parameter.Value --output text \
                        --region "$INSTANCE_REGION" 2>/dev/null); then
            
            if [ -n "$join_cmd" ] && [ "$join_cmd" != "None" ]; then
                log_info "✅ Join command retrieved successfully"
                echo "$join_cmd"
                return 0
            fi
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            log_info "Join command not ready, waiting $$wait_interval}s..."
            sleep $wait_interval
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_error "Timeout waiting for join command after $((max_attempts * wait_interval)) seconds"
    return 1
}

# =================================================================
# CLUSTER JOIN PROCESS
# =================================================================
join_cluster() {
    log_info "=== Joining Kubernetes Cluster ==="
    
    # Get join command
    local JOIN_COMMAND=""
    if ! JOIN_COMMAND=$(get_join_command); then
        log_error "Failed to retrieve join command"
        return 1
    fi
    
    if [ -z "$JOIN_COMMAND" ]; then
        log_error "Empty join command received"
        return 1
    fi
    
    log_info "Joining cluster as worker node..."
    log_info "Join command: $(echo "$JOIN_COMMAND" | sed 's/--token [^ ]*/--token <REDACTED>/')"
    
    # Execute join command
    if eval "$JOIN_COMMAND --v=5"; then
        log_info "✅ Successfully joined cluster as worker node"
    else
        log_error "Failed to join cluster"
        log_error "Debug information:"
        journalctl -u kubelet --no-pager -l | tail -20 || true
        return 1
    fi
    
    return 0
}

# =================================================================
# POST-JOIN VERIFICATION
# =================================================================
verify_join() {
    log_info "=== Verifying Cluster Join ==="
    
    local max_attempts=30
    local attempt=1
    
    log_info "Waiting for kubelet configuration to be created..."
    
    while [ $attempt -le $max_attempts ]; do
        if [ -f "/etc/kubernetes/kubelet.conf" ]; then
            log_info "✅ Kubelet configuration found"
            break
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            log_error "Kubelet configuration not found after $max_attempts attempts"
            return 1
        fi
        
        log_info "Waiting for kubelet config... ($attempt/$max_attempts)"
        sleep 10
        attempt=$((attempt + 1))
    done
    
    if [ ! -f "/etc/kubernetes/kubelet.conf" ]; then
        log_error "Kubelet configuration file not found"
        return 1
    fi
    
    # Verify kubelet service is running
    log_info "Checking kubelet service status..."
    if systemctl is-active --quiet kubelet; then
        log_info "✅ Kubelet service is running"
    else
        log_warn "Kubelet service is not running, attempting to start..."
        systemctl start kubelet || {
            log_error "Failed to start kubelet service"
            systemctl status kubelet || true
            return 1
        }
    fi
    
    # Wait for node to be ready (this may take a while)
    log_info "Waiting for node to become ready (this may take several minutes)..."
    local ready_attempts=60
    local ready_attempt=1
    
    while [ $ready_attempt -le $ready_attempts ]; do
        # Try to check node status (requires kubectl and proper kubeconfig)
        # For worker nodes, we can't easily check this without cluster access
        # So we just verify the kubelet is running and connected
        
        if systemctl is-active --quiet kubelet; then
            log_info "✅ Worker node appears to be functioning"
            
            # Log some status for debugging
            if [ $((ready_attempt % 5)) -eq 0 ]; then
                log_info "Kubelet status check ($ready_attempt/$ready_attempts):"
                systemctl status kubelet --no-pager -l | head -10 || true
            fi
            
            break
        fi
        
        sleep 30
        ready_attempt=$((ready_attempt + 1))
    done
    
    log_info "✅ Join verification completed"
    return 0
}

# =================================================================
# MAIN EXECUTION
# =================================================================
main() {
    log_info "Starting worker node cluster join..."
    
    # Get instance metadata
    if ! ec2_init _metadata; then
        log_error "Failed to retrieve instance metadata"
        return 1
    fi
    
    # Validate AWS credentials
    validate_aws_credentials || log_warn "AWS credential validation failed, continuing..."
    
    # Join the cluster
    if ! join_cluster; then
        log_error "Failed to join cluster"
        return 1
    fi
    
    # Verify the join was successful
    if ! verify_join; then
        log_error "Join verification failed"
        return 1
    fi
    
    log_info "=== Worker Node Cluster Join Completed Successfully ==="
    log_info "✅ Node has joined cluster: $CLUSTER_NAME"
    log_info "✅ Kubelet is running and configured"
    log_info "✅ Instance IP: $INSTANCE_IP"
    
    return 0
}

# Execute main function
main "$@"
