#!/bin/bash
# 03-setup-load-balancer.sh
# Refactored to use shared functions architecture
# Sets up AWS Network Load Balancer and DNS for Kubernetes API server high availability

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

setup_logging "setup-load-balancer"

log_info "Starting Load Balancer setup with log level: ${LOG_LEVEL}"

if [ -z "$SYSTEM_PREPARED" ] && [ ! -f "/tmp/.system_prepared" ]; then
    log_info "System not yet prepared, running preparation..."
    prepare_system_once
else
    log_info "System already prepared, skipping preparation"
fi

# =================================================================
# SHARED EC2 METADATA
# =================================================================
source "${SCRIPT_DIR}/001-ec2-metadata-lib.sh"
ec2_init_metadata || exit 1

# Initialize metadata (will cache for other scripts)
if ! ec2_init_metadata; then
    echo "FATAL: Failed to retrieve EC2 metadata" >&2
    exit 1
fi

# =================================================================
# CONFIGURATION VARIABLES (from Terraform)
# =================================================================
readonly PRIMARY_PARAM="/k8s/${CLUSTER_NAME}/primary-controller-${JOIN_CMD_SUFFIX}"
readonly NLB_PARAM="/k8s/${CLUSTER_NAME}/nlb-arn}"
readonly TARGET_GROUP_PARAM="/k8s/${CLUSTER_NAME}/target-group-arn}"
readonly DNS_PARAM="/${CLUSTER_NAME}/api-dns-name"

# Kubernetes API port
readonly API_PORT=6443

log_info "=== Load Balancer and DNS Configuration Started ==="
log_info "Cluster Name: ${CLUSTER_NAME}"
log_info "API DNS Name: ${API_DNS_NAME}"
log_info "Cluster Domain: ${CLUSTER_DOMAIN}"
log_info "VPC ID: ${VPC_ID}"
log_info "Hosted Zone ID: ${HOSTED_ZONE_ID}"

# =================================================================
# PREREQUISITE CHECKS
# =================================================================
check_prerequisites() {
    log_info "=== Checking Prerequisites ==="
    
    # Check required environment variables
    local required_vars=("CLUSTER_NAME" "VPC_ID" "SUBNET_IDS" "INSTANCE_REGION")
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            log_error "Required environment variable not set: ${var}"
            return 1
        fi
    done
    
    # Check Route53 requirements only if enabled
    if [ "${USE_ROUTE53}" = "true" ]; then
        if [ -z "${HOSTED_ZONE_ID}" ]; then
            log_error "HOSTED_ZONE_ID required when USE_ROUTE53=true"
            return 1
        fi
        
        # Verify hosted zone exists
        if ! aws route53 get-hosted-zone --id "${HOSTED_ZONE_ID}" >/dev/null 2>&1; then
            log_error "Hosted Zone ${HOSTED_ZONE_ID} not found or not accessible"
            return 1
        fi
    else
        log_info "Route53 DNS disabled - will use NLB DNS name directly"
    fi
    
    # Check AWS CLI availability and permissions
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI not available or not configured properly"
        return 1
    fi
    
    # Verify VPC exists
    if ! aws ec2 describe-vpcs --vpc-ids "${VPC_ID}" --region "${INSTANCE_REGION}" >/dev/null 2>&1; then
        log_error "VPC ${VPC_ID} not found or not accessible"
        return 1
    fi
    
    log_info "✅ Prerequisites check passed"
    return 0
}

# =================================================================
# NETWORK LOAD BALANCER CREATION
# =================================================================
create_network_load_balancer() {
    log_info "=== Creating Network Load Balancer ==="
    
    # Check if NLB already exists
    local existing_nlb_arn=""
    if existing_nlb_arn=$(aws ssm get-parameter --name "${NLB_PARAM}" \
                           --query Parameter.Value --output text \
                           --region "${INSTANCE_REGION}" 2>/dev/null); then
        
        # Verify NLB still exists in AWS
        if aws elbv2 describe-load-balancers --load-balancer-arns "${existing_nlb_arn}" \
             --region "${INSTANCE_REGION}" >/dev/null 2>&1; then
            log_info "✅ Network Load Balancer already exists: ${existing_nlb_arn}"
            echo "${existing_nlb_arn}"
            return 0
        else
            log_warn "Stored NLB ARN exists but NLB not found in AWS, creating new one"
        fi
    fi
    
    # Convert comma-separated subnet IDs to space-separated for AWS CLI
    local clean_subnet_ids="${SUBNET_IDS//\"/}"

    # Split on spaces
    local -a subnet_array
    IFS=' ' read -r -a subnet_array <<< "${clean_subnet_ids}"
    
    if [ ${#subnet_array[@]} -eq 0 ] || [ -z "${subnet_array[0]}" ]; then
        log_error "No subnet IDs provided"
        return 1
    fi

    log_info "Creating Network Load Balancer with subnets: ${subnet_array[*]}"
    
    # Create the NLB
    local nlb_arn=""
    if nlb_arn=$(aws elbv2 create-load-balancer \
                   --name "${CLUSTER_NAME}-nlb" \
                   --scheme internal \
                   --type network \
                   --ip-address-type ipv4 \
                   --subnets "${subnet_array[@]}" \
                   --tags Key=Name,Value="${CLUSTER_NAME}-api-nlb" \
                          Key=Cluster,Value="${CLUSTER_NAME}" \
                          Key=Component,Value="kubernetes-api" \
                   --region "${INSTANCE_REGION}" \
                   --query 'LoadBalancers[0].LoadBalancerArn' \
                   --output text); then
        
        log_info "✅ Network Load Balancer created: ${nlb_arn}"
        
        # Store NLB ARN in SSM
        if aws ssm put-parameter --name "${NLB_PARAM}" \
             --value "${nlb_arn}" --type "String" --overwrite \
             --region "${INSTANCE_REGION}" >/dev/null 2>&1; then
            log_info "✅ NLB ARN stored in SSM"
        else
            log_error "Failed to store NLB ARN in SSM"
            return 1
        fi
        
        echo ${nlb_arn}
        return 0
    else
        log_error "Failed to create Network Load Balancer"
        return 1
    fi
}

# =================================================================
# TARGET GROUP CREATION
# =================================================================
create_target_group() {
    log_info "=== Creating Target Group ==="
    
    local nlb_arn="$1"
    if [ -z "${nlb_arn}" ]; then
        log_error "NLB ARN required for target group creation"
        return 1
    fi
    
    # Check if target group already exists
    local existing_tg_arn=""
    if existing_tg_arn=$(aws ssm get-parameter --name "${TARGET_GROUP_PARAM}" \
                          --query Parameter.Value --output text \
                          --region "${INSTANCE_REGION}" 2>/dev/null); then
        
        # Verify target group still exists in AWS
        if aws elbv2 describe-target-groups --target-group-arns "${existing_tg_arn}" \
             --region "${INSTANCE_REGION}" >/dev/null 2>&1; then
            log_info "✅ Target Group already exists: ${existing_tg_arn}"
            echo "${existing_tg_arn}"
            return 0
        else
            log_warn "Stored Target Group ARN exists but target group not found in AWS, creating new one"
        fi
    fi
    
    log_info "Creating Target Group for Kubernetes API..."
    
    # Create target group
    tg_arn=""
    if tg_arn=$(aws elbv2 create-target-group \
                  --name "${CLUSTER_NAME}-tg" \
                  --protocol TCP \
                  --port ${API_PORT} \
                  --vpc-id "${VPC_ID}" \
                  --target-type instance \
                  --health-check-protocol TCP \
                  --health-check-port ${API_PORT} \
                  --health-check-interval-seconds 10 \
                  --healthy-threshold-count 2 \
                  --unhealthy-threshold-count 2 \
                  --tags Key=Name,Value="${CLUSTER_NAME}-tg" \
                         Key=Cluster,Value="${CLUSTER_NAME}" \
                         Key=Component,Value="kubernetes-api" \
                  --region "${INSTANCE_REGION}" \
                  --query 'TargetGroups[0].TargetGroupArn' \
                  --output text); then
        
        log_info "✅ Target Group created: ${tg_arn}"
        
        # Store Target Group ARN in SSM
        if aws ssm put-parameter --name "${TARGET_GROUP_PARAM}" \
             --value "${tg_arn}" --type "String" --overwrite \
             --region "${INSTANCE_REGION}" >/dev/null 2>&1; then
            log_info "✅ Target Group ARN stored in SSM"
        else
            log_error "Failed to store Target Group ARN in SSM"
            return 1
        fi
        
        echo ${tg_arn}
        return 0
    else
        log_error "Failed to create Target Group"
        return 1
    fi
}

# =================================================================
# LISTENER CREATION
# =================================================================
create_listener() {
    log_info "=== Creating Load Balancer Listener ==="
    local nlb_arn="$1"
    local tg_arn="$2"

    # Sanitize ARNs (remove surrounding quotes)
    nlb_arn=$(echo "${nlb_arn}" | sed -e 's/^["'\'']//' -e 's/["'\'']$//')
    tg_arn=$(echo "${tg_arn}" | sed -e 's/^["'\'']//' -e 's/["'\'']$//')

    # Validate NLB ARN format
    if ! [[ "$nlb_arn" =~ ^arn:aws:elasticloadbalancing:.*:loadbalancer/net/ ]]; then
        log_error "Invalid NLB ARN format: $nlb_arn"
        return 1
    fi

    # Validate TG ARN format
    if ! [[ "$tg_arn" =~ ^arn:aws:elasticloadbalancing:.*:targetgroup/ ]]; then
        log_error "Invalid Target Group ARN format: $tg_arn"
        return 1
    fi
    
    # Check if listener already exists
    if aws elbv2 describe-listeners --load-balancer-arn "${nlb_arn}" \
         --region "${INSTANCE_REGION}" --query "Listeners[?Port==\`6443\`]" \
         --output text | grep -q "${API_PORT}"; then
        log_info "✅ Listener already exists for port ${API_PORT}"
        return 0
    fi
    
    log_info "Creating listener for port ${API_PORT}..."
    
    # Create listener
    if aws elbv2 create-listener \
        --load-balancer-arn "${nlb_arn}" \
        --protocol TCP \
        --port "${API_PORT}" \
        --default-actions "[{\"Type\":\"forward\",\"TargetGroupArn\":\"${tg_arn}\"}]" \
        --region "${INSTANCE_REGION}" >/dev/null; then
        log_info "✅ Listener created successfully"
        return 0
    else
        log_error "Failed to create listener"
        return 1
    fi
}

# =================================================================
# TARGET REGISTRATION
# =================================================================
register_controller_instances() {
    log_info "=== Registering Controller Instances ==="
    
    local tg_arn="$1"
    if [ -z "${tg_arn}" ]; then
        log_error "Target Group ARN required for instance registration"
        return 1
    fi
    
    # Get all controller instances for this cluster
    log_info "Finding controller instances for cluster: ${CLUSTER_NAME}"
    
    local controller_instances=""
    controller_instances=$(aws ec2 describe-instances \
                            --filters "Name=tag:ClusterControllerType,Values=${CLUSTER_NAME}-controller" \
                                     "Name=tag:Role,Values=controller" \
                                     "Name=instance-state-name,Values=running" \
                            --query 'Reservations[].Instances[].InstanceId' \
                            --output text \
                            --region "${INSTANCE_REGION}")
    
    if [ -z "${controller_instances}" ]; then
        log_error "No running controller instances found for cluster ${CLUSTER_NAME}"
        return 1
    fi
    
    log_info "Found controller instances: ${controller_instances}"
    
    # Register each instance with the target group
    for instance_id in ${controller_instances}; do
        log_info "Registering instance ${instance_id} with target group..."
        
        if aws elbv2 register-targets \
             --target-group-arn "${tg_arn}" \
             --targets Id="${instance_id},Port=${API_PORT}" \
             --region "${INSTANCE_REGION}" >/dev/null; then
            
            log_info "✅ Instance ${instance_id} registered successfully"
        else
            log_error "Failed to register instance ${instance_id}"
            # Don't fail the whole operation for one instance
        fi
    done
    
    # Wait for targets to become healthy
    log_info "Waiting for targets to become healthy..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local healthy_count=""
        healthy_count=$(aws elbv2 describe-target-health \
                         --target-group-arn "${tg_arn}" \
                         --region "${INSTANCE_REGION}" \
                         --query "TargetHealthDescriptions[?TargetHealth.State=='healthy']" \
                         --output text | wc -l)
        
        local current_attempt=$((attempt + 1))
        log_info "Healthy targets: ${healthy_count} \(attempt ${current_attempt}/${max_attempts}\)"
        
        if [ "${healthy_count}" -gt 0 ]; then
            log_info "✅ At least one target is healthy"
            break
        fi
        
        if [ $attempt -eq $((max_attempts - 1)) ]; then
            log_warn "Timeout waiting for healthy targets, but continuing..."
            # Show current target health for debugging
            aws elbv2 describe-target-health \
              --target-group-arn "${tg_arn}" \
              --region "${INSTANCE_REGION}" || true
        fi
        
        attempt=$((attempt + 1))
        sleep 10
    done
    
    return 0
}

# =================================================================
# DNS CONFIGURATION
# =================================================================
get_nlb_dns_name() {
    log_info "=== Getting NLB DNS Name ==="
    
    local nlb_arn="$1"
    if [ -z "${nlb_arn}" ]; then
        log_error "NLB ARN required to get DNS name"
        return 1
    fi
    
    local nlb_dns_name=""
    if nlb_dns_name=$(aws elbv2 describe-load-balancers \
                       --load-balancer-arns "${nlb_arn}" \
                       --region "${INSTANCE_REGION}" \
                       --query 'LoadBalancers[0].DNSName' \
                       --output text); then
        
        log_info "✅ NLB DNS Name: ${nlb_dns_name}"
        echo "${nlb_dns_name}"
        return 0
    else
        log_error "Failed to get NLB DNS name"
        return 1
    fi
}

create_dns_record() {
    log_info "=== Creating DNS Record ==="
    
    local nlb_dns_name="$1"
    if [ -z "${nlb_dns_name}" ]; then
        log_error "NLB DNS name required for DNS record creation"
        return 1
    fi
    
    # Skip Route53 if not enabled
    if [ "${USE_ROUTE53}" != "true" ]; then
        log_info "Route53 disabled, skipping DNS record creation"
        log_info "Use NLB DNS name directly: ${nlb_dns_name}"
        
        # Store NLB DNS name as the API DNS name for later use
        if aws ssm put-parameter --name "${DNS_PARAM}" \
             --value "${nlb_dns_name}" --type "String" --overwrite \
             --region "${INSTANCE_REGION}" >/dev/null 2>&1; then
            log_info "✅ NLB DNS name stored in SSM"
        fi
        
        return 0
    fi
    
    log_info "Creating DNS record: ${API_DNS_NAME} -> ${nlb_dns_name}"
    
    # Create Route53 change batch
    local change_batch
    change_batch=$(cat <<DNS_BATCH
{
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "${API_DNS_NAME}",
                "Type": "CNAME",
                "TTL": 300,
                "ResourceRecords": [
                    {
                        "Value": "${nlb_dns_name}"
                    }
                ]
            }
        }
    ]
}
DNS_BATCH
)
    
    # Apply the DNS change
    local change_id=""
    if change_id=$(aws route53 change-resource-record-sets \
                    --hosted-zone-id "${HOSTED_ZONE_ID}" \
                    --change-batch "${change_batch}" \
                    --query 'ChangeInfo.Id' \
                    --output text); then
        
        log_info "✅ DNS record change submitted: ${change_id}"
        
        # Wait for change to propagate
        log_info "Waiting for DNS change to propagate..."
        if aws route53 wait resource-record-sets-changed --id "${change_id}"; then
            log_info "✅ DNS change propagated successfully"
        else
            log_warn "DNS change propagation timed out, but may still be working"
        fi
        
        # Store DNS name in SSM
        if aws ssm put-parameter --name "${DNS_PARAM}" \
             --value "${API_DNS_NAME}" --type "String" --overwrite \
             --region "${INSTANCE_REGION}" >/dev/null 2>&1; then
            log_info "✅ DNS name stored in SSM"
        else
            log_error "Failed to store DNS name in SSM"
        fi
        
        return 0
    else
        log_error "Failed to create DNS record"
        return 1
    fi
}

# =================================================================
# KUBECONFIG UPDATE
# =================================================================
update_kubeconfig_for_dns() {
    log_info "=== Updating Kubeconfig for Load Balancer ==="
    
    local nlb_dns_name="$1"
    local kubeconfig_path="/etc/kubernetes/admin.conf"
    
    # Check if kubeconfig exists
    if [ ! -f "${kubeconfig_path}" ]; then
        log_warn "Kubeconfig not found at ${kubeconfig_path}, skipping update"
        return 0
    fi
    
    # Determine which DNS name to use
    local target_dns_name=""
    if [ "${USE_ROUTE53}" = "true" ]; then
        target_dns_name="${API_DNS_NAME}"
        log_info "Updating kubeconfig server URL to use custom DNS name: ${target_dns_name}"
    else
        target_dns_name="${nlb_dns_name}"
        log_info "Updating kubeconfig server URL to use NLB DNS name: ${target_dns_name}"
    fi
    
    # Backup original kubeconfig
    cp "${kubeconfig_path}" "${kubeconfig_path}.backup.$(date +%s)"
    
    # Update server URL in kubeconfig
    if sed -i "s|server: https://.*:6443|server: https://${target_dns_name}:6443|g" "${kubeconfig_path}"; then
        log_info "✅ Kubeconfig updated successfully"
        
        # Test the updated configuration
        if KUBECONFIG="${kubeconfig_path}" kubectl cluster-info >/dev/null 2>&1; then
            log_info "✅ Updated kubeconfig is functional"
        else
            log_warn "Updated kubeconfig test failed, but this may be temporary"
        fi
    else
        log_error "Failed to update kubeconfig"
        return 1
    fi
    
    return 0
}

# =================================================================
# VERIFICATION
# =================================================================
verify_load_balancer_setup() {
    log_info "=== Verifying Load Balancer Setup ==="
    
    # Determine which DNS name to test
    local test_dns_name=""
    if [ "${USE_ROUTE53}" = "true" ]; then
        test_dns_name="${API_DNS_NAME}"
        
        # Test DNS resolution
        log_info "Testing DNS resolution for ${test_dns_name}..."
        if nslookup "${test_dns_name}" >/dev/null 2>&1; then
            log_info "✅ DNS resolution successful"
            local resolved_ip=""
            resolved_ip=$(nslookup "${test_dns_name}" | grep -A1 "Name:" | tail -1 | awk '{print $2}')
            log_info "Resolved to: ${resolved_ip}"
        else
            log_warn "DNS resolution failed, may need time to propagate"
        fi
    else
        # Get NLB DNS name from SSM
        test_dns_name=$(aws ssm get-parameter --name "${DNS_PARAM}" \
                         --query Parameter.Value --output text \
                         --region "${INSTANCE_REGION}" 2>/dev/null)
        log_info "Using NLB DNS name directly: ${test_dns_name}"
    fi
    
    # Test API connectivity through load balancer
    if [ -n "${test_dns_name}" ]; then
        log_info "Testing API connectivity through load balancer..."
        if curl -k -s --connect-timeout 10 "https://${test_dns_name}:${API_PORT}/healthz" >/dev/null 2>&1; then
            log_info "✅ API accessible through load balancer"
        else
            log_warn "API not yet accessible through load balancer may need time for health checks"
        fi
    fi
    
    # Show final configuration
    log_info "Load balancer configuration summary:"
    log_info "  API Endpoint: https://${test_dns_name}:${API_PORT}"
    log_info "  Route53 DNS: ${USE_ROUTE53}"
    log_info "  Cluster: ${CLUSTER_NAME}"
    
    return 0
}

# =================================================================
# MAIN EXECUTION
# =================================================================
main() {
    log_info "Starting Load Balancer and DNS setup..."
    
    # Check prerequisites
    if ! check_prerequisites; then
        log_error "Prerequisites check failed"
        return 1
    fi
    
    # Create Network Load Balancer
    local nlb_arn=""
    if nlb_arn=$(create_network_load_balancer); then
        log_info "Got NLB_ARN: ${nlb_arn}"
    else
        log_error "Failed to create Network Load Balancer"
        return 1
    fi
    
    # Create Target Group
    local tg_arn=""
    if tg_arn=$(create_target_group "${nlb_arn}"); then
        log_info "Got TG_ARN: ${tg_arn}"
    else
        log_error "Failed to create Target Group"
        return 1
    fi
    
    # Create Listener
    if ! create_listener "${nlb_arn}" "${tg_arn}"; then
        log_error "Failed to create Listener"
        return 1
    fi
    
    # Register controller instances
    if ! register_controller_instances "${tg_arn}"; then
        log_error "Failed to register controller instances"
        return 1
    fi
    
    # Get NLB DNS name and create DNS record
    local nlb_dns_name=""
    if ! nlb_dns_name=$(get_nlb_dns_name "${nlb_arn}"); then
        log_error "Failed to get NLB DNS name"
        return 1
    fi
    
    if ! create_dns_record "${nlb_dns_name}"; then
        log_error "Failed to create DNS record"
        return 1
    fi
    
    # Update kubeconfig to use load balancer
    if ! update_kubeconfig_for_dns "${nlb_dns_name}"; then
        log_warn "Failed to update kubeconfig, but continuing..."
    fi
    
    # Verify setup
    verify_load_balancer_setup
    
    log_info "=== Load Balancer and DNS Setup Completed Successfully ==="
    log_info "✅ Network Load Balancer: ${nlb_arn}"
    log_info "✅ Target Group: ${tg_arn}"
    
    if [ "${USE_ROUTE53}" = "true" ]; then
        log_info "✅ DNS Record: ${API_DNS_NAME}"
        log_info "✅ Cluster API accessible via: https://${API_DNS_NAME}:${API_PORT}"
    else
        log_info "✅ Using NLB DNS name: ${nlb_dns_name}"
        log_info "✅ Cluster API accessible via: https://${nlb_dns_name}:${API_PORT}"
    fi
    
    return 0
}

# Execute main function
main "$@"
