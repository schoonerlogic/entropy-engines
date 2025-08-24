#!/bin/bash
# scripts/cleanup-nlb-from-ssm.sh
set -e

CLUSTER_NAME=${CLUSTER_NAME:-""}
INSTANCE_REGION=${INSTANCE_REGION:-"us-west-2"}
NLB_PARAM=${NLB_PARAM:-"/k8s/${CLUSTER_NAME}/nlb/arn"}

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

clean_arn() {
    echo "$1" | tr -d '\r\n\t ' | sed 's/^"//;s/"$//'
}

# Comprehensive target group discovery with proper parsing
find_all_target_groups() {
    local nlb_arn="$1"
    local all_target_groups=()
    
    log_info "Finding all target groups for cluster: ${CLUSTER_NAME}"
    
    # Method 1: From NLB listeners (if NLB exists)
    if [[ -n "$nlb_arn" ]]; then
        log_info "Getting target groups from NLB listeners..."
        while IFS= read -r tg_arn; do
            if [[ -n "$tg_arn" && "$tg_arn" != "None" && "$tg_arn" =~ ^arn:aws:elasticloadbalancing: ]]; then
                all_target_groups+=("$tg_arn")
                log_info "Found target group from listener: $tg_arn"
            fi
        done < <(aws elbv2 describe-listeners \
            --load-balancer-arn "$nlb_arn" \
            --region "${INSTANCE_REGION}" \
            --query "Listeners[].DefaultActions[?Type=='forward'].TargetGroupArn" \
            --output text 2>/dev/null | tr '\t' '\n')
    fi
    
    # Method 2: By naming convention
    log_info "Searching target groups by naming convention..."
    while IFS= read -r tg_arn; do
        if [[ -n "$tg_arn" && "$tg_arn" != "None" && "$tg_arn" =~ ^arn:aws:elasticloadbalancing: ]]; then
            # Check if already in array to avoid duplicates
            local found=false
            for existing in "${all_target_groups[@]}"; do
                if [[ "$existing" == "$tg_arn" ]]; then
                    found=true
                    break
                fi
            done
            if [[ "$found" == false ]]; then
                all_target_groups+=("$tg_arn")
                log_info "Found target group by name: $tg_arn"
            fi
        fi
    done < <(aws elbv2 describe-target-groups \
        --region "${INSTANCE_REGION}" \
        --query "TargetGroups[?contains(TargetGroupName, '${CLUSTER_NAME}')].TargetGroupArn" \
        --output text 2>/dev/null | tr '\t' '\n')
    
    # Return array as space-separated string
    printf "%s\n" "${all_target_groups[@]}"
}

cleanup_target_groups() {
    local deleted_count=0
    local failed_count=0
    
    # Read target groups from stdin (one per line)
    local target_groups=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            target_groups+=("$line")
        fi
    done
    
    if [[ ${#target_groups[@]} -eq 0 ]]; then
        log_info "No target groups found to delete"
        return 0
    fi
    
    log_info "Found ${#target_groups[@]} target groups to clean up"
    
    for tg_arn in "${target_groups[@]}"; do
        # Validate ARN format
        if [[ ! "$tg_arn" =~ ^arn:aws:elasticloadbalancing:.+:targetgroup/.+ ]]; then
            log_error "Invalid target group ARN format: ${tg_arn}"
            ((failed_count++))
            continue
        fi
        
        log_info "Processing target group: ${tg_arn}"
        
        # First, deregister any remaining targets
        local targets
        targets=$(aws elbv2 describe-target-health \
            --target-group-arn "$tg_arn" \
            --region "${INSTANCE_REGION}" \
            --query "TargetHealthDescriptions[].Target" \
            --output json 2>/dev/null || echo "[]")
        
        if [[ "$targets" != "[]" && "$targets" != "" && "$targets" != "null" ]]; then
            log_info "Deregistering targets from $tg_arn..."
            echo "$targets" | jq -r '.[] | "\(.Id) \(.Port // 80)"' 2>/dev/null | while read -r target_id port; do
                if [[ -n "$target_id" && "$target_id" != "null" ]]; then
                    aws elbv2 deregister-targets \
                        --target-group-arn "$tg_arn" \
                        --targets Id="$target_id",Port="$port" \
                        --region "${INSTANCE_REGION}" 2>/dev/null || true
                fi
            done
            
            # Wait a moment for deregistration
            sleep 5
        fi
        
        # Delete the target group
        if aws elbv2 delete-target-group \
             --target-group-arn "$tg_arn" \
             --region "${INSTANCE_REGION}" 2>/dev/null; then
            log_info "✅ Successfully deleted target group: ${tg_arn}"
            ((deleted_count++))
        else
            log_error "❌ Failed to delete target group: ${tg_arn}"
            ((failed_count++))
        fi
    done
    
    log_info "Target group cleanup summary: ${deleted_count} deleted, ${failed_count} failed"
}

cleanup_nlb() {
    log_info "=== Cleaning up NLB resources for cluster: ${CLUSTER_NAME} ==="
    
    local nlb_arn=""
    local found_nlb=false
    
    # Method 1: Try to get NLB ARN from SSM parameter
    if nlb_arn_raw=$(aws ssm get-parameter \
        --name "${NLB_PARAM}" \
        --region "${INSTANCE_REGION}" \
        --query 'Parameter.Value' \
        --output text 2>/dev/null); then
        
        nlb_arn=$(clean_arn "$nlb_arn_raw")
        if [[ -n "$nlb_arn" && "$nlb_arn" != "None" ]]; then
            log_info "Found NLB ARN from SSM: ${nlb_arn}"
            found_nlb=true
        fi
    fi
    
    # Method 2: If no SSM parameter, find by naming convention
    if [[ "$found_nlb" == false ]]; then
        log_info "No SSM parameter found, searching by naming convention..."
        nlb_arn=$(aws elbv2 describe-load-balancers \
            --region "${INSTANCE_REGION}" \
            --query "LoadBalancers[?LoadBalancerName=='${CLUSTER_NAME}-nlb'].LoadBalancerArn" \
            --output text 2>/dev/null | head -1)
        
        if [[ -n "$nlb_arn" && "$nlb_arn" != "None" ]]; then
            nlb_arn=$(clean_arn "$nlb_arn")
            log_info "Found NLB by name: ${nlb_arn}"
            found_nlb=true
        fi
    fi
    
    # Method 3: Find by tags as last resort
    if [[ "$found_nlb" == false ]]; then
        log_info "Searching by tags..."
        nlb_arn=$(aws elbv2 describe-load-balancers \
            --region "${INSTANCE_REGION}" \
            --output json 2>/dev/null | jq -r \
            ".LoadBalancers[] | select(.Tags[]? | select(.Key == \"Cluster\" and .Value == \"${CLUSTER_NAME}\")) | .LoadBalancerArn" \
            | head -1)
        
        if [[ -n "$nlb_arn" && "$nlb_arn" != "None" && "$nlb_arn" != "null" ]]; then
            log_info "Found NLB by tags: ${nlb_arn}"
            found_nlb=true
        fi
    fi
    
    # Find all target groups regardless of whether NLB exists
    log_info "Discovering all target groups..."
    local all_target_groups
    all_target_groups=$(find_all_target_groups "$nlb_arn")
    
    # If NLB exists, delete it first
    if [[ "$found_nlb" == true ]]; then
        # Verify NLB actually exists
        if aws elbv2 describe-load-balancers \
             --load-balancer-arns "$nlb_arn" \
             --region "${INSTANCE_REGION}" >/dev/null 2>&1; then
            
            # Disable deletion protection
            log_info "Disabling deletion protection for NLB..."
            aws elbv2 modify-load-balancer-attributes \
                --load-balancer-arn "$nlb_arn" \
                --attributes Key=deletion_protection.enabled,Value=false \
                --region "${INSTANCE_REGION}" >/dev/null 2>&1 || true
            
            # Delete the NLB
            log_info "Deleting Network Load Balancer: ${nlb_arn}"
            if aws elbv2 delete-load-balancer \
                 --load-balancer-arn "$nlb_arn" \
                 --region "${INSTANCE_REGION}"; then
                log_info "✅ NLB deletion initiated"
                
                # Wait for NLB deletion
                log_info "Waiting for NLB deletion to complete..."
                local wait_count=0
                while [[ $wait_count -lt 30 ]]; do
                    if ! aws elbv2 describe-load-balancers \
                         --load-balancer-arns "$nlb_arn" \
                         --region "${INSTANCE_REGION}" >/dev/null 2>&1; then
                        log_info "✅ NLB successfully deleted"
                        break
                    fi
                    sleep 10
                    ((wait_count++))
                done
            else
                log_error "Failed to delete NLB: ${nlb_arn}"
            fi
        else
            log_info "NLB ARN found but LB doesn't exist anymore"
        fi
    else
        log_info "No NLB found for cluster ${CLUSTER_NAME}"
    fi
    
    # Clean up all target groups
    if [[ -n "$all_target_groups" ]]; then
        echo "$all_target_groups" | cleanup_target_groups
    else
        log_info "No target groups found to clean up"
    fi
    
    # Clean up SSM parameter
    log_info "Removing NLB ARN from SSM..."
    aws ssm delete-parameter \
        --name "${NLB_PARAM}" \
        --region "${INSTANCE_REGION}" 2>/dev/null || \
        log_info "SSM parameter ${NLB_PARAM} not found or already deleted"
    
    log_info "✅ Complete cleanup finished for cluster: ${CLUSTER_NAME}"
}

# Main execution
if [[ -z "$CLUSTER_NAME" ]]; then
    log_error "CLUSTER_NAME environment variable is required"
    exit 1
fi

cleanup_nlb
