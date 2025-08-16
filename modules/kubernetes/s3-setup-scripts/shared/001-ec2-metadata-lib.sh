#!/bin/bash

# EC2 Metadata Service Library for Terraform-Generated Scripts
# Source this file to access EC2 metadata functions
# Fixed for partial $$ escaping behavior in this Terraform environment

# Prevent multiple sourcing
if [ -n "$EC2_METADATA_LIB_LOADED" ] 2>/dev/null; then
    return 0
fi
readonly EC2_METADATA_LIB_LOADED=1

# Configuration constants
readonly EC2_METADATA_BASE_URL="http://169.254.169.254/latest"
readonly EC2_TOKEN_TTL="21600"
readonly EC2_MAX_RETRIES=5
readonly EC2_INITIAL_DELAY=2
readonly EC2_MAX_DELAY=30
readonly EC2_METADATA_TIMEOUT=10
readonly EC2_METADATA_CONNECT_TIMEOUT=5
readonly EC2_METADATA_CACHE_FILE="/opt/aws-instance-metadata"

# Global state variables
EC2_METADATA_TOKEN=""
EC2_METADATA_INITIALIZED=0

# Set DEBUG default if not already set by environment
if [ -z "$DEBUG" ] 2>/dev/null; then
    DEBUG=0
fi

# Logging Functions
ec2_log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*" >&2
}

ec2_log_warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $*" >&2
}

ec2_log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

ec2_log_debug() {
    # Safe check for DEBUG variable - use a subshell to avoid unbound variable errors
    if ([ -n "$DEBUG" ] && [ "$DEBUG" = "1" ]) 2>/dev/null; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] DEBUG: $*" >&2
    fi
}

# Retry function with exponential backoff
ec2_retry_with_backoff() {
    local max_attempts="$1"
    local delay="$2"
    local max_delay="$3"
    shift 3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        ec2_log_debug "Attempt $attempt/$max_attempts: $*"
        
        if "$@"; then
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            local sleep_time=$((delay * (2 ** (attempt - 1))))
            if [ $sleep_time -gt $max_delay ]; then
                sleep_time=$max_delay
            fi
            ec2_log_debug "Retrying in $$sleep_time}s..."
            sleep $sleep_time
        fi
        
        attempt=$((attempt + 1))
    done
    
    return 1
}

# Check if running on EC2
ec2_is_instance() {
    # Check for EC2 hypervisor UUID
    if [ -r /sys/hypervisor/uuid ] && [ "$(head -c 3 /sys/hypervisor/uuid 2>/dev/null)" = "ec2" ]; then
        return 0
    fi
    
    # Check DMI data if available
    if command -v dmidecode >/dev/null 2>&1; then
        if dmidecode -s system-manufacturer 2>/dev/null | grep -qi amazon; then
            return 0
        fi
    fi
    
    # Final check: metadata service reachability
    curl -s --connect-timeout 3 --max-time 5 "$EC2_METADATA_BASE_URL/" >/dev/null 2>&1
}

# Validate IP address format
ec2_validate_ip() {
    local ip="$1"
    local ip_regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
    
    if echo "$ip" | grep -qE "$ip_regex"; then
        # Check each octet is <= 255
        local first_octet second_octet third_octet fourth_octet
        first_octet=$(echo "$ip" | cut -d'.' -f1)
        second_octet=$(echo "$ip" | cut -d'.' -f2)
        third_octet=$(echo "$ip" | cut -d'.' -f3)
        fourth_octet=$(echo "$ip" | cut -d'.' -f4)
        
        if [ $first_octet -le 255 ] && [ $second_octet -le 255 ] && [ $third_octet -le 255 ] && [ $fourth_octet -le 255 ]; then
            return 0
        fi
    fi
    
    return 1
}

# Parse JSON field safely
ec2_parse_json_field() {
    local json="$1"
    local field="$2"
    
    # Try jq first (most reliable)
    if command -v jq >/dev/null 2>&1; then
        local result
        if result=$(echo "$json" | jq -r ".$field" 2>/dev/null) && [ "$result" != "null" ] && [ -n "$result" ]; then
            echo "$result"
            return 0
        fi
    fi
    
    # Fallback to regex parsing
    local pattern='"'"$field"'":[[:space:]]*"([^"]*)"'

if echo "$json" | grep -qE "$pattern"; then
    echo "$json" | sed -n 's/.*'"$pattern"'.*/\1/p'
    return 0
fi
    
    return 1
}

# Get IMDSv2 token
ec2_get_token() {
    ec2_log_debug "Requesting new IMDSv2 token"
    
    local token
    if ! token=$(ec2_retry_with_backoff $EC2_MAX_RETRIES $EC2_INITIAL_DELAY $EC2_MAX_DELAY \
                   curl -X PUT \
                   -H "X-aws-ec2-metadata-token-ttl-seconds: $EC2_TOKEN_TTL" \
                   --silent --show-error \
                   --connect-timeout $EC2_METADATA_CONNECT_TIMEOUT \
                   --max-time $EC2_METADATA_TIMEOUT \
                   "$EC2_METADATA_BASE_URL/api/token" 2>/dev/null); then
        ec2_log_error "Failed to obtain IMDSv2 token after $EC2_MAX_RETRIES attempts"
        return 1
    fi
    
    if [ -z "$token" ] || [ $#token} -lt 10 ]; then
        ec2_log_error "Invalid or empty token received"
        return 1
    fi
    
    # Set global token variable
    EC2_METADATA_TOKEN="$token"
    ec2_log_debug "Successfully obtained IMDSv2 token (length: $$#token})"
    return 0
}

# Ensure we have a valid token
ec2_ensure_token() {
    if [ -z "$EC2_METADATA_TOKEN" ]; then
        ec2_get_token || return 1
    fi
    return 0
}

# Generic metadata fetcher
ec2_get_metadata_raw() {
    local endpoint="$1"
    
    ec2_ensure_token || return 1
    
    ec2_log_debug "Fetching metadata from endpoint: $endpoint"
    
    local result
    if ! result=$(ec2_retry_with_backoff $EC2_MAX_RETRIES $EC2_INITIAL_DELAY $EC2_MAX_DELAY \
                    curl -H "X-aws-ec2-metadata-token: $EC2_METADATA_TOKEN" \
                    --silent --show-error --fail \
                    --connect-timeout $EC2_METADATA_CONNECT_TIMEOUT \
                    --max-time $EC2_METADATA_TIMEOUT \
                    "$EC2_METADATA_BASE_URL/$endpoint" 2>/dev/null); then
        ec2_log_error "Failed to fetch metadata from $endpoint"
        return 1
    fi
    
    if [ -z "$result" ]; then
        ec2_log_error "Empty result from metadata endpoint: $endpoint"
        return 1
    fi
    
    echo "$result"
}

# Get instance private IP
ec2_get_instance_ip() {
    local ip
    if ! ip=$(ec2_get_metadata_raw "meta-data/local-ipv4"); then
        return 1
    fi
    
    if ! ec2_validate_ip "$ip"; then
        ec2_log_error "Retrieved invalid IP address: $ip"
        return 1
    fi
    
    echo "$ip"
}

# Get instance public IP (may not exist)
ec2_get_public_ip() {
    ec2_get_metadata_raw "meta-data/public-ipv4" 2>/dev/null || echo ""
}

# Get instance ID
ec2_get_instance_id() {
    ec2_get_metadata_raw "meta-data/instance-id"
}

# Get instance type
ec2_get_instance_type() {
    ec2_get_metadata_raw "meta-data/instance-type"
}

# Get availability zone
ec2_get_availability_zone() {
    ec2_get_metadata_raw "meta-data/placement/availability-zone"
}

# Get region from instance identity document
ec2_get_region() {
    local identity_doc
    if ! identity_doc=$(ec2_get_metadata_raw "dynamic/instance-identity/document"); then
        return 1
    fi
    
    ec2_parse_json_field "$identity_doc" "region"
}

# Get instance identity document
ec2_get_identity_document() {
    ec2_get_metadata_raw "dynamic/instance-identity/document"
}

# Initialize all EC2 metadata and make it globally available
ec2_init_metadata() {
    if [ $EC2_METADATA_INITIALIZED -eq 1 ]; then
        ec2_log_debug "EC2 metadata already initialized"
        return 0
    fi
    
    ec2_log_info "Initializing EC2 instance metadata"
    
    # Verify we're on an EC2 instance
    if ! ec2_is_instance; then
        ec2_log_error "Not running on an EC2 instance or metadata service unreachable"
        return 1
    fi
    
    # Get token first
    if ! ec2_get_token; then
        ec2_log_error "Cannot proceed without IMDSv2 token"
        return 1
    fi
    
    # Get instance IP
    ec2_log_info "Retrieving instance IP address"
    if ! AWS_INSTANCE_IP=$(ec2_get_instance_ip); then
        ec2_log_error "Failed to retrieve instance IP"
        return 1
    fi
    
    # Get instance identity document for multiple fields
    ec2_log_info "Retrieving instance identity information"
    local identity_document
    if ! identity_document=$(ec2_get_identity_document); then
        ec2_log_error "Failed to retrieve instance identity document"
        return 1
    fi
    
    # Parse all fields from identity document
    if ! AWS_REGION=$(ec2_parse_json_field "$identity_document" "region"); then
        ec2_log_error "Failed to parse region"
        return 1
    fi
    
    if ! AWS_AVAILABILITY_ZONE=$(ec2_parse_json_field "$identity_document" "availabilityZone"); then
        ec2_log_warn "Failed to parse availability zone"
        AWS_AVAILABILITY_ZONE=""
    fi
    
    if ! AWS_INSTANCE_ID=$(ec2_parse_json_field "$identity_document" "instanceId"); then
        ec2_log_warn "Failed to parse instance ID"
        AWS_INSTANCE_ID=""
    fi
    
    if ! AWS_INSTANCE_TYPE=$(ec2_parse_json_field "$identity_document" "instanceType"); then
        ec2_log_warn "Failed to parse instance type"
        AWS_INSTANCE_TYPE=""
    fi
    
    if ! AWS_ACCOUNT_ID=$(ec2_parse_json_field "$identity_document" "accountId"); then
        ec2_log_warn "Failed to parse account ID"
        AWS_ACCOUNT_ID=""
    fi
    
    # Get public IP (optional)
    AWS_PUBLIC_IP=$(ec2_get_public_ip)
    
    # Declare all variables as global and export them
    export AWS_INSTANCE_IP AWS_PUBLIC_IP AWS_REGION AWS_AVAILABILITY_ZONE AWS_INSTANCE_ID AWS_INSTANCE_TYPE AWS_ACCOUNT_ID AWS_METADATA_TOKEN
    
    # Legacy compatibility - also declare global  
    export INSTANCE_IP="$AWS_INSTANCE_IP"
    export INSTANCE_REGION="$AWS_REGION"
    
    # Cache to file for persistence across script runs
    ec2_cache_metadata
    
    EC2_METADATA_INITIALIZED=1
    
    ec2_log_info "EC2 metadata initialization complete"
    ec2_log_info "Instance: $AWS_INSTANCE_ID ($AWS_INSTANCE_TYPE)"
    ec2_log_info "Private IP: $AWS_INSTANCE_IP"
    ec2_log_info "Region: $AWS_REGION ($AWS_AVAILABILITY_ZONE)"
    
    return 0
}

# Cache metadata to file for use by other scripts
ec2_cache_metadata() {
    cat > "$EC2_METADATA_CACHE_FILE" << 'EOF'
# AWS Instance Metadata - Generated $$(date -u +%Y-%m-%dT%H:%M:%SZ)
AWS_INSTANCE_ID=$AWS_INSTANCE_ID
AWS_INSTANCE_IP=$AWS_INSTANCE_IP
AWS_PUBLIC_IP=$AWS_PUBLIC_IP
AWS_REGION=$AWS_REGION
AWS_AVAILABILITY_ZONE=$AWS_AVAILABILITY_ZONE
AWS_INSTANCE_TYPE=$AWS_INSTANCE_TYPE
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
INSTANCE_IP=$AWS_INSTANCE_IP
INSTANCE_REGION=$AWS_REGION
METADATA_UPDATED=$$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
    
    chmod 644 "$EC2_METADATA_CACHE_FILE"
    ec2_log_debug "Metadata cached to $EC2_METADATA_CACHE_FILE"
}

# Load cached metadata from previous script runs
ec2_load_cached_metadata() {
    if [ -f "$EC2_METADATA_CACHE_FILE" ]; then
        ec2_log_debug "Loading cached metadata from $EC2_METADATA_CACHE_FILE"
        # Source the cached file
        set +u  # Temporarily allow undefined variables
        source "$EC2_METADATA_CACHE_FILE"
        set -u
        
        # Verify critical fields are present and valid
        if [ -n "$AWS_INSTANCE_IP" ] && [ -n "$AWS_REGION" ]; then
            # Export all variables
            export AWS_INSTANCE_IP AWS_PUBLIC_IP AWS_REGION AWS_AVAILABILITY_ZONE AWS_INSTANCE_ID AWS_INSTANCE_TYPE AWS_ACCOUNT_ID
            
            # Legacy compatibility
            export INSTANCE_IP="$AWS_INSTANCE_IP"
            export INSTANCE_REGION="$AWS_REGION"
            
            EC2_METADATA_INITIALIZED=1
            ec2_log_debug "Successfully loaded cached metadata"
            return 0
        fi
    fi
    
    ec2_log_debug "No valid cached metadata found"
    return 1
}

# Smart metadata initialization - use cache if available, fetch if not
ec2_ensure_metadata() {
    if [ $EC2_METADATA_INITIALIZED -ne 1 ]; then
        if ! ec2_load_cached_metadata; then
            ec2_init_metadata || return 1
        fi
    fi
    return 0
}

# Force refresh of metadata (ignores cache)
ec2_refresh_metadata() {
    EC2_METADATA_INITIALIZED=0
    EC2_METADATA_TOKEN=""
    ec2_init_metadata
}

# Print current metadata status (useful for debugging)
ec2_status() {
    echo "=== EC2 Metadata Status ==="
    echo "Initialized: $EC2_METADATA_INITIALIZED"
    echo "Instance ID: $AWS_INSTANCE_ID"
    echo "Private IP: $AWS_INSTANCE_IP"
    echo "Public IP: $AWS_PUBLIC_IP"
    echo "Region: $AWS_REGION"
    echo "AZ: $AWS_AVAILABILITY_ZONE"
    echo "Instance Type: $AWS_INSTANCE_TYPE"
    echo "Account ID: $AWS_ACCOUNT_ID"
    if [ -n "$EC2_METADATA_TOKEN" ]; then
        echo "Token Set: YES"
    else
        echo "Token Set: NO"
    fi
    echo "Cache File: $EC2_METADATA_CACHE_FILE"
    if [ -f "$EC2_METADATA_CACHE_FILE" ]; then
        echo "Cache Exists: YES"
    else
        echo "Cache Exists: NO"
    fi
}

# Wait for metadata service to be available (useful during early boot)
ec2_wait_for_metadata_service() {
    local max_attempts=30
    local attempt=1
    
    ec2_log_info "Waiting for EC2 metadata service to become available"
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s --connect-timeout 2 --max-time 5 "$EC2_METADATA_BASE_URL/" >/dev/null 2>&1; then
            ec2_log_info "Metadata service is available"
            return 0
        fi
        
        ec2_log_debug "Metadata service not ready, attempt $attempt/$max_attempts"
        sleep 5
        attempt=$((attempt + 1))
    done
    
    ec2_log_error "Metadata service did not become available after $max_attempts attempts"
    return 1
}

# Get just the instance IP (will initialize metadata if needed)
ec2_get_ip() {
    ec2_ensure_metadata || return 1
    echo "$AWS_INSTANCE_IP"
}

# Get just the region (will initialize metadata if needed)  
ec2_get_aws_region() {
    ec2_ensure_metadata || return 1
    echo "$AWS_REGION"
}

# Get just the instance ID (will initialize metadata if needed)
ec2_get_aws_instance_id() {
    ec2_ensure_metadata || return 1
    echo "$AWS_INSTANCE_ID"
}

# Get provider ID for Kubernetes
ec2_get_k8s_provider_id() {
    ec2_ensure_metadata || return 1
    echo "aws://$AWS_AVAILABILITY_ZONE/$AWS_INSTANCE_ID"
}

# Get hostname for Kubernetes (uses instance ID by default)
ec2_get_k8s_hostname() {
    ec2_ensure_metadata || return 1
    if [ -n "$K8S_HOSTNAME" ]; then
        echo "$K8S_HOSTNAME"
    else
        echo "$AWS_INSTANCE_ID"
    fi
}

# Generate kubelet extra args for AWS
ec2_get_kubelet_extra_args() {
    ec2_ensure_metadata || return 1
    echo "--node-ip=$AWS_INSTANCE_IP --provider-id=aws://$AWS_AVAILABILITY_ZONE/$AWS_INSTANCE_ID --cloud-provider=aws"
}

# Uncomment the next line to automatically ensure metadata is available when library is sourced
# This adds ~2-3 seconds to script startup but ensures variables are always ready
# ec2_ensure_metadata >/dev/null 2>&1 || true
