#!/bin/bash
# 03-setup-load-balancer.sh
# Refactored to use shared functions architecture
# Sets up AWS Network Load Balancer and DNS for Kubernetes API server high availability
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

setup_logging "setup-load-balancer"

log_info "Starting Load Balancer setup with log level: ${LOG_LEVEL}"

if [ -z "$SYSTEM_PREPARED" ] && [ ! -f "/tmp/.system_prepared" ]; then
    log_info "System not yet prepared, running preparation..."
    prepare_system_once
else
    log_info "System already prepared, skipping preparation"
fi

# Load EC2 metadata 
source "${SCRIPT_DIR}/001-ec2-metadata-lib.sh"
ec2_init_metadata || exit 1

# Initialize metadata (will cache for other scripts)
if ! ec2_init_metadata; then
    echo "FATAL: Failed to retrieve EC2 metadata" >&2
    exit 1
fi

# =================================================================
# CONFIGURATION VARIABLES (from .env files)
# =================================================================
readonly PRIMARY_PARAM="/k8s/${CLUSTER_NAME}/primary-controller-${JOIN_CMD_SUFFIX}"

# Kubernetes API port
readonly API_PORT=6443

# =================================================================
# HELPER FUNCTIONS
# =================================================================
clean_arn() {
    local str=$1
    # remove leading / trailing ASCII whitespace and single/double quotes
    str=${str#[$' \t\n\r\"\'']}
    str=${str%[$' \t\n\r\"\'']}
    printf '%s\n' "$str"
}

# =================================================================
# PREREQUISITE CHECKS
# =================================================================
check_prerequisites() {
    log_info "=== Checking Prerequisites ==="
    
    local required_vars=("CLUSTER_NAME" "VPC_ID" "SUBNET_IDS" "INSTANCE_REGION")

    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            log_error "Required environment variable not set: ${var}"
            return 1
        fi
    done
    
    if [ "${USE_ROUTE53}" = "true" ] && [ -z "${HOSTED_ZONE_ID}" ]; then
        log_error "HOSTED_ZONE_ID required when USE_ROUTE53=true"
        return 1
    fi

    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI not configured"
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
    msg=$(aws ssm get-parameter \
        --name "${NLB_PARAM}" \
        --region "${INSTANCE_REGION}" \
        --query 'Parameter.Value' \
        --output text 2>&1)
    rc=$?

    if [[ $rc -eq 0 ]]; then
      # Success – clean and validate the ARN
      existing_arn=$(clean_arn "$msg")
     
      if aws elbv2 describe-load-balancers \
           --load-balancer-arns "$existing_arn" \
           --region "${INSTANCE_REGION}" >/dev/null 2>&1; then
        log_info "✅ NLB already exists: ${existing_arn}"
        echo "$existing_arn"
        return 0
      else
        log_warn "SSM ARN invalid or NLB deleted (ARN=$existing_arn)"
      fi
    else
        # Failure – log whatever the CLI put on stderr
        log_error "Failed to read '${NLB_PARAM}' from SSM: $msg"
    fi

 

    # Split on spaces
    local -a subnet_array
    IFS=' ' read -r -a subnet_array <<< "${SUBNET_IDS}"
    
    if [ ${#subnet_array[@]} -eq 0 ] || [ -z "${subnet_array[0]}" ]; then
        log_error "No subnet IDs provided"
        return 1
    fi

    log_info "Creating Network Load Balancer with subnets: ${subnet_array[*]}"
    
    # Create the NLB
    local nlb_arn
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
        
        nlb_arn=$(clean_arn "$nlb_arn")
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
    local existing_tg_arn
    if existing_tg_arn=$(aws ssm get-parameter --name "${TARGET_GROUP_PARAM}" \
                          --query Parameter.Value --output text \
                          --region "${INSTANCE_REGION}" 2>/dev/null)
      existing_tg_arn=$(clean_arn "${existing_tg_arn}"); then
    
      if aws elbv2 describe-target-groups --target-group-arns "${existing_tg_arn}" \
             --region "${INSTANCE_REGION}" >/dev/null 2>&1; then
          log_info "✅ Target Group already exists: ${existing_tg_arn}"
          echo "${existing_tg_arn}"
          return 0
      else
          log_warn "Stored Target Group ARN not found (invalid or deleted), creating new"
      fi
    fi 
    
    log_info "Creating Target Group for Kubernetes API..."
    
    # Create target group
    tg_arn
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
        tg_arn=$(clean_arn "$tg_arn")
        
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

    nlb_arn=$(clean_arn "$nlb_arn")
    tg_arn=$(clean_arn "$tg_arn")

    listeners=$(aws elbv2 describe-listeners \
              --load-balancer-arn "${nlb_arn}" \
              --region "${INSTANCE_REGION}" \
              --query "length(Listeners[?Port==\`${API_PORT}\`])" \
              --output text)

    if [[ ${listeners:-0} -gt 0 ]]; then
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
        log_info "✅ Listener created"
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
    tg_arn=$(clean_arn "$tg_arn")
  
    local controller_instances
    controller_instances=$(aws ec2 describe-instances \
                            --filters "Name=tag:ClusterControllerType,Values=${CLUSTER_NAME}-controller" \
                                     "Name=instance-state-name,Values=running" \
                            --query 'Reservations[].Instances[].InstanceId' \
                            --output text \
                            --region "${INSTANCE_REGION}")
    
    aws_exit_code=$?
    echo "AWS CLI exit code: $aws_exit_code"
    echo "Controller instances found: '${controller_instances}'"

    if [ $aws_exit_code -ne 0 ]; then
        log_error "AWS CLI failed with error: ${controller_instances}"
        return 1
    fi

    if [ -z "${controller_instances}" ]; then
        log_error "No running controller instances found for cluster ${CLUSTER_NAME}"
        return 1
    fi
    
    log_info "Found controller instances: ${controller_instances}"
    
    local registered_ids
    registered_ids=$(aws elbv2 describe-target-health \
        --target-group-arn "$tg_arn" \
        --region "${INSTANCE_REGION}" \
        --query 'TargetHealthDescriptions[].Target.Id' \
        --output text 2>/dev/null || echo "")


    # Register each instance with the target group
    for instance_id in ${controller_instances}; do
        if echo "$registered_ids" | grep -qw "$instance_id"; then
            log_info "Instance $instance_id already registered, skipping"
            continue
        fi

        log_info "Registering instance ${instance_id}"
        
        if aws elbv2 register-targets \
             --target-group-arn "${tg_arn}" \
             --targets Id="${instance_id},Port=${API_PORT}" \
             --region "${INSTANCE_REGION}" >/dev/null; then
            
            log_info "✅ Instance ${instance_id} registered successfully"
        else
            log_error "Failed to register instance ${instance_id}"
        fi
    done

    log_info "Waiting for *all* controller targets to become healthy …"
    max_wait=300           # seconds
    interval=10

    end_time=$(($(date +%s) + max_wait))
    
# First, get all target health info for debugging
    all_targets=$(aws elbv2 describe-target-health \
        --target-group-arn "${tg_arn}" \
        --region "${INSTANCE_REGION}" \
        2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        echo "Error: AWS CLI command failed"
        break
    fi
    
    echo "All targets: $all_targets"
    
    # Now get unhealthy targets
    mapfile -t unhealthy < <(
        aws elbv2 describe-target-health \
          --target-group-arn "${tg_arn}" \
          --region "${INSTANCE_REGION}" \
          --query "TargetHealthDescriptions[?TargetHealth.State!='healthy' && TargetHealth.State!='Healthy'].Target.Id" \
          --output text 2>/dev/null | grep -v '^$'
    )
    
    echo "Unhealthy targets count: ${#unhealthy[@]}"
    echo "Unhealthy targets: ${unhealthy[*]}"
    

    while [[ $(date +%s) -lt $end_time ]]; do
        mapfile -t unhealthy < <(
            aws elbv2 describe-target-health \
              --target-group-arn "${tg_arn}" \
              --region "${INSTANCE_REGION}" \
              --query "TargetHealthDescriptions[?TargetHealth.State!='healthy'].Target.Id" \
              --output text
        )

        if [[ ${#unhealthy[@]} -eq 0 ]]; then
            log_info "✅ All controller targets are healthy"
            break
        fi

        log_info "Still waiting for: ${unhealthy[*]} (${#unhealthy[@]} unhealthy)"
        sleep "$interval"
    done

    if [[ ${#unhealthy[@]} -gt 0 ]]; then
        log_error "Timed out waiting for healthy targets: ${unhealthy[*]}"
        return 1
    fi
    return 0
}

# =================================================================
# DNS CONFIGURATION
# =================================================================
get_nlb_dns_name() {
    log_info "=== Getting NLB DNS Name ==="
    
    local nlb_arn="$1"
    nlb_arn=$(clean_arn "$nlb_arn")
    
    local nlb_dns
    if nlb_dns=$(aws elbv2 describe-load-balancers \
                       --load-balancer-arns "${nlb_arn}" \
                       --region "${INSTANCE_REGION}" \
                       --query 'LoadBalancers[0].DNSName' \
                       --output text); then
        
        log_info "✅ NLB DNS Name: ${nlb_dns}"
        printf '%s\n' "${nlb_dns}"
    else
        log_error "Failed to get NLB DNS"
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
    
    lb_zone_id=$(aws elbv2 describe-load-balancers \
               --load-balancer-arns "$nlb_arn" \
               --query 'LoadBalancers[0].CanonicalHostedZoneId' \
               --output text)

    change_batch=$(jq -n \
      --arg name "$API_DNS_NAME" \
      --arg nlb_zone "$lb_zone_id" \
      --arg nlb_dns "$nlb_dns_name" \
    '{
      Changes: [{
        Action: "UPSERT",
        ResourceRecordSet: {
          Name: $name,
          Type: "A",
          AliasTarget: {
            HostedZoneId: $nlb_zone,
            DNSName: $nlb_dns,
            EvaluateTargetHealth: false
          }
        }
      }]
    }')

    if aws route53 change-resource-record-sets \
        --hosted-zone-id "${hosted_zone_id}" \
        --change-batch "$change_batch" \
        --region "${INSTANCE_REGION}" >/dev/null; then
        log_info "✅ Route53 A record created"
        aws ssm put-parameter --name "${DNS_PARAM}" --value "${API_DNS_NAME}" --type String --overwrite --region "${INSTANCE_REGION}" >/dev/null
        echo "${API_DNS_NAME}"
    else
        log_warn "Failed to create Route53 record"
        echo "$nlb_dns_name"
    fi
}

# =================================================================
# KUBECONFIG UPDATE
# =================================================================
update_kubeconfig_for_dns() {
    log_info "=== Updating Kubeconfig for Load Balancer ==="
    
    local target_dns_name="$1"
    local kubeconfig=${2:-/etc/kubernetes/admin.conf}
    
    # Check if kubeconfig exists
    if [ ! -f "${kubeconfig}" ]; then
        log_warn "Kubeconfig not found at ${kubeconfig}, skipping update"
        return 0
    fi
    
    # Determine which DNS name to use
    if [ "${USE_ROUTE53}" = "true" ]; then
        target_dns_name="${API_DNS_NAME}"
        log_info "Updating kubeconfig server URL to use custom DNS name: ${target_dns_name}"
    else
      log_info "Updating kubeconfig server URL to use NLB DNS name: ${target_dns_name}"
  fi
  
  # Backup original kubeconfig
  cp "${kubeconfig}" "${kubeconfig}.backup.$(date +%s)"
  
  # Create a *new* file, leave the original untouched
    local tmp
    tmp=$(mktemp /tmp/kubeconfig.XXXXXX)
    cp "$kubeconfig" "$tmp"

    cluster_name=$(kubectl config view --kubeconfig="$tmp" -o jsonpath='{.clusters[0].name}')
    kubectl config set-cluster "$cluster_name" \
      --server="https://${target_dns_name}:6443" \
      --kubeconfig="$tmp" >/dev/null

    # Optionally move it back (or leave the new file for the caller)
    mv "$tmp" "$kubeconfig"
    chown root:root "$kubeconfig"
    chmod 600 "$kubeconfig"

    log_info "✅ Kubeconfig updated to https://${target_dns_name}:6443"
  
    # --- after the file has been moved into place ---
    log_info "Testing connectivity with updated kubeconfig ..."
    local retries=15          # ~2.5 minutes
    while (( retries > 0 )); do
        if KUBECONFIG="${kubeconfig}" kubectl cluster-info &>/dev/null; then
            log_info "✅ Updated kubeconfig is functional"
            return 0
        fi
        log_info "Waiting for DNS / NLB health ... ($retries)"
        ((retries--))
        sleep 10
    done

    log_error "Updated kubeconfig test still failing after retries"
    return 1
}

# =================================================================
# VERIFICATION
# =================================================================
verify_load_balancer_setup() {
    log_info "=== Verifying Load-Balancer Setup ==="

    local test_dns_name
    if [[ ${USE_ROUTE53} == "true" ]]; then
        test_dns_name=${API_DNS_NAME}
    else
        test_dns_name=$(aws ssm get-parameter \
                          --name "${DNS_PARAM}" \
                          --region "${INSTANCE_REGION}" \
                          --query 'Parameter.Value' \
                          --output text 2>/dev/null) || {
            log_error "Could not fetch NLB DNS from SSM"
            return 1
        }
    fi
    log_info "Testing endpoint: https://${test_dns_name}:${API_PORT}"

    # DNS resolution
      local ip
      local max_dns_retries=12
      local dns_retry_delay=10
      local dns_resolved=false

      # DNS resolution with retry logic using getent (more reliable)
      for ((i=1; i<=max_dns_retries; i++)); do
          log_info "DNS resolution attempt $i/$max_dns_retries for ${test_dns_name}"
          
          # Use getent for DNS resolution - more reliable than dig
          if ip=$(getent ahosts "${test_dns_name}" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | awk '{print $1}') && [[ -n $ip ]]; then
              log_info "✅ DNS resolves to: ${ip}"
              dns_resolved=true
              break
          fi
          
          if [ $i -lt $max_dns_retries ]; then
              log_warn "DNS resolution failed, retrying in ${dns_retry_delay}s..."
              sleep ${dns_retry_delay}
          else
              log_error "❌ DNS resolution failed after $max_dns_retries attempts"
              log_warn "Proceeding with health checks despite DNS resolution failure"
          fi
      done

      # Wait for API health endpoint
      local health_retries=12
      local health_retry_delay=10
      local health_success=false

      for ((i=1; i<=health_retries; i++)); do
          log_info "Health check attempt $i/$health_retries for https://${test_dns_name}:${API_PORT}/healthz"
          
          # Use curl with proper timeouts
          if curl -kfsS --connect-timeout 5 --max-time 10 \
                  "https://${test_dns_name}:${API_PORT}/healthz" >/dev/null 2>&1; then
              log_info "✅ API accessible through load balancer"
              health_success=true
              break
          fi
          
          if [ $i -lt $health_retries ]; then
              log_warn "Health check failed, retrying in ${health_retry_delay}s..."
              sleep ${health_retry_delay}
          else
              log_error "❌ Health check failed after $health_retries attempts"
          fi
      done

      if [[ "$health_success" != "true" ]]; then
          log_error "❌ API still unreachable after all retries"
          return 1
      fi

      log_info "Summary:"
      log_info "  API Endpoint: https://${test_dns_name}:${API_PORT}"
      log_info "  Resolved IP : ${ip:-Not resolved}"
      log_info "  Route53 DNS : ${USE_ROUTE53}"
      log_info "  Cluster     : ${CLUSTER_NAME}"
   return 0
}


########################################
# Globals we want the caller to inherit
########################################
export NLB_ARN="" TG_ARN="" NLB_DNS_NAME=""


########################################
# MAIN
########################################
main() 
    log_info "Starting Load Balancer and DNS setup..."

    check_prerequisites || { log_error "Prerequisites failed"; return 2; }

    # NLB_ARN=$(create_network_load_balancer)          || return 1
    # TG_ARN=$(create_target_group "$NLB_ARN")         || return 1
    # create_listener "$NLB_ARN" "$TG_ARN"             || return 1
    register_controller_instances "$TG_ARN"          || return 1

    NLB_DNS_NAME=$(get_nlb_dns_name "$NLB_ARN")      || return 1
    create_dns_record "$NLB_DNS_NAME"                || return 1

    update_kubeconfig_for_dns "$NLB_DNS_NAME"        || log_warn "Kubeconfig update failed"

    # Ensure the endpoint is actually reachable
    verify_load_balancer_setup                       || return 1

    ############################################################
    # One-line JSON summary for external automation
    ############################################################
    jq -n \
       --arg nlb_arn "$NLB_ARN" \
       --arg tg_arn "$TG_ARN" \
       --arg dns "$([[ $USE_ROUTE53 == true ]] && echo "$API_DNS_NAME" || echo "$NLB_DNS_NAME")" \
       --arg port "$API_PORT" \
    '{status: "success", nlb_arn: $nlb_arn, tg_arn: $tg_arn, api_endpoint: ("https://" + $dns + ":" + $port)}'

    log_info "=== Load Balancer and DNS Setup Completed Successfully ==="
    return 0
}

main "$@"

