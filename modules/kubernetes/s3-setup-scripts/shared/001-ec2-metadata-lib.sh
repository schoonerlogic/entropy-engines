#!/bin/bash
# Enhanced EC2 Metadata Library with Instance IP retrieval

# Prevent multiple sourcing
echo "============================="
echo "= Loading MetaData Library  ="
echo "============================="

# Guard against multiple loading
if [ "${EC2_METADATA_LIB_LOADED:-0}" = "1" ] && command -v ec2_get_token >/dev/null 2>&1; then
    echo "EC2 metadata library already loaded"
    return 0
fi

EC2_METADATA_LIB_LOADED=1
export EC2_METADATA_LIB_LOADED

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
INSTANCE_IP=""
INSTANCE_ID=""
INSTANCE_REGION=""

# Set DEBUG default if not already set by environment
if [ -z "$DEBUG" ] 2>/dev/null; then
    DEBUG=0
fi

# Enhanced logging functions for metadata library
ec2_log_debug() {
    if [ "$DEBUG" = "1" ]; then
        echo "[EC2-DEBUG $(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
    fi
}

ec2_log_info() {
    echo "[EC2-INFO $(date '+%Y-%m-%d %H:%M:%S')] $*"
}

ec2_log_error() {
    echo "[EC2-ERROR $(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Check if we're running on EC2
ec2_check_environment() {
    ec2_log_debug "Checking if running on EC2"
    
    # Quick connectivity test
    if ! curl -s --connect-timeout 3 --max-time 5 "$EC2_METADATA_BASE_URL" >/dev/null 2>&1; then
        ec2_log_error "Cannot reach EC2 metadata service - not running on EC2 or network issue"
        return 1
    fi
    
    ec2_log_debug "Metadata service is accessible"
    return 0
}

# Enhanced token retrieval with detailed debugging
ec2_get_token() {
    ec2_log_debug "Requesting new IMDSv2 token"
    
    local token_url="$EC2_METADATA_BASE_URL/api/token"
    local response
    local http_code
    local curl_exit_code
    
    ec2_log_debug "Token URL: $token_url"
    ec2_log_debug "Token TTL: $EC2_TOKEN_TTL seconds"
    
    # Make the request
    response=$(curl -X PUT \
        -H "X-aws-ec2-metadata-token-ttl-seconds: $EC2_TOKEN_TTL" \
        --silent --fail \
        --connect-timeout $EC2_METADATA_CONNECT_TIMEOUT \
        --max-time $EC2_METADATA_TIMEOUT \
        "$token_url" 2>&1)
    
    curl_exit_code=$?
    
    if [ $curl_exit_code -ne 0 ]; then
        ec2_log_error "Failed to obtain IMDSv2 token (curl exit: $curl_exit_code)"
        ec2_log_debug "Curl error: $response"
        return 1
    fi
    
    # Basic validation - AWS tokens are typically 40-100+ characters
    if [ -z "$response" ] || [ ${#response} -lt 30 ]; then
        ec2_log_error "Invalid token received (length: ${#response}): $response"
        return 1
    fi
    
    # Basic format validation (should be base64-like)
    if ! echo "$response" | grep -qE '^[A-Za-z0-9+/=_-]+$'; then
        ec2_log_error "Token contains invalid characters: ${response:0:50}..."
        return 1
    fi
    
    # Set global token variable
    EC2_METADATA_TOKEN="$response"
    ec2_log_debug "Successfully obtained IMDSv2 token (length: ${#response})"
    return 0
}

# Get metadata using IMDSv2 token
ec2_get_metadata() {
    local endpoint="$1"
    local full_url="$EC2_METADATA_BASE_URL/meta-data/$endpoint"
    
    if [ -z "$EC2_METADATA_TOKEN" ]; then
        ec2_log_error "No metadata token available"
        return 1
    fi
    
    ec2_log_debug "Fetching metadata: $endpoint"
    
    local response
    response=$(curl -s -f \
        -H "X-aws-ec2-metadata-token: $EC2_METADATA_TOKEN" \
        --connect-timeout $EC2_METADATA_CONNECT_TIMEOUT \
        --max-time $EC2_METADATA_TIMEOUT \
        "$full_url" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$response" ]; then
        echo "$response"
        return 0
    else
        ec2_log_error "Failed to fetch metadata: $endpoint"
        return 1
    fi
}

# Get instance private IP address
ec2_get_instance_ip() {
    ec2_log_debug "Retrieving instance private IP"
    
    local ip
    if ip=$(ec2_get_metadata "local-ipv4"); then
        # Validate IP format
        if echo "$ip" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
            echo "$ip"
            return 0
        else
            ec2_log_error "Invalid IP format received: $ip"
            return 1
        fi
    else
        ec2_log_error "Failed to retrieve instance IP"
        return 1
    fi
}

# Get instance ID
ec2_get_instance_id() {
    ec2_log_debug "Retrieving instance ID"
    
    local instance_id
    if instance_id=$(ec2_get_metadata "instance-id"); then
        if [ -n "$instance_id" ]; then
            echo "$instance_id"
            return 0
        fi
    fi
    
    ec2_log_error "Failed to retrieve instance ID"
    return 1
}

# Get instance region
ec2_get_instance_region() {
    ec2_log_debug "Retrieving instance region"
    
    local az region
    if az=$(ec2_get_metadata "placement/availability-zone"); then
        # Extract region from AZ (remove last character)
        region=${az%?}
        if [ -n "$region" ]; then
            echo "$region"
            return 0
        fi
    fi
    
    ec2_log_error "Failed to retrieve instance region"
    return 1
}

# Initialize metadata service and retrieve core instance info
ec2_init_metadata() {
    if [ "$EC2_METADATA_INITIALIZED" = "1" ]; then
        ec2_log_debug "Metadata already initialized"
        return 0
    fi
    
    ec2_log_info "Initializing EC2 instance metadata"
    
    # Check environment first
    if ! ec2_check_environment; then
        ec2_log_error "EC2 environment check failed"
        return 1
    fi
    
    # Get initial token
    if ! ec2_get_token; then
        ec2_log_error "Cannot proceed without IMDSv2 token"
        return 1
    fi
    
    # Retrieve and cache core instance information
    ec2_log_info "Retrieving core instance information..."
    
    # Get instance IP
    if INSTANCE_IP=$(ec2_get_instance_ip); then
        export INSTANCE_IP
        ec2_log_info "Instance IP: $INSTANCE_IP"
    else
        ec2_log_error "Failed to retrieve instance IP"
        return 1
    fi
    
    # Get instance ID
    if INSTANCE_ID=$(ec2_get_instance_id); then
        export INSTANCE_ID
        ec2_log_info "Instance ID: $INSTANCE_ID"
    else
        ec2_log_error "Failed to retrieve instance ID"
        return 1
    fi
    
    # Get instance region
    if INSTANCE_REGION=$(ec2_get_instance_region); then
        export INSTANCE_REGION
        ec2_log_info "Instance Region: $INSTANCE_REGION"
    else
        ec2_log_error "Failed to retrieve instance region"
        return 1
    fi
    
    # Cache the information to file for other processes
    {
        echo "INSTANCE_IP=$INSTANCE_IP"
        echo "INSTANCE_ID=$INSTANCE_ID"
        echo "INSTANCE_REGION=$INSTANCE_REGION"
        echo "EC2_METADATA_TOKEN=$EC2_METADATA_TOKEN"
    } > "$EC2_METADATA_CACHE_FILE"
    
    EC2_METADATA_INITIALIZED=1
    ec2_log_info "EC2 metadata initialization completed successfully"
    
    return 0
}

# Load cached metadata if available
ec2_load_cached_metadata() {
    if [ -f "$EC2_METADATA_CACHE_FILE" ]; then
        ec2_log_debug "Loading cached metadata from $EC2_METADATA_CACHE_FILE"
        source "$EC2_METADATA_CACHE_FILE"
        
        # Verify cache is still valid
        if [ -n "$INSTANCE_IP" ] && [ -n "$INSTANCE_ID" ] && [ -n "$INSTANCE_REGION" ]; then
            export INSTANCE_IP INSTANCE_ID INSTANCE_REGION EC2_METADATA_TOKEN
            EC2_METADATA_INITIALIZED=1
            ec2_log_info "Loaded cached metadata: IP=$INSTANCE_IP, ID=$INSTANCE_ID, Region=$INSTANCE_REGION"
            return 0
        fi
    fi
    return 1
}

# Test function to diagnose issues
ec2_diagnose() {
    echo "=== EC2 Metadata Diagnostics ==="
    
    echo "Environment:"
    echo "  DEBUG: ${DEBUG:-0}"
    echo "  EC2_METADATA_LIB_LOADED: ${EC2_METADATA_LIB_LOADED:-0}"
    echo "  EC2_METADATA_INITIALIZED: ${EC2_METADATA_INITIALIZED:-0}"
    
    echo "Current Values:"
    echo "  INSTANCE_IP: ${INSTANCE_IP:-<not set>}"
    echo "  INSTANCE_ID: ${INSTANCE_ID:-<not set>}"
    echo "  INSTANCE_REGION: ${INSTANCE_REGION:-<not set>}"
    
    echo "Network connectivity:"
    if curl -s --connect-timeout 3 --max-time 5 "$EC2_METADATA_BASE_URL" >/dev/null; then
        echo "  ✓ Can reach metadata service"
    else
        echo "  ✗ Cannot reach metadata service"
    fi
    
    echo "IMDSv2 token test:"
    if [ -n "$EC2_METADATA_TOKEN" ]; then
        echo "  ✓ Token available (length: ${#EC2_METADATA_TOKEN})"
        
        # Test token by fetching instance ID
        local test_id
        if test_id=$(ec2_get_metadata "instance-id"); then
            echo "  ✓ Token works, instance ID: $test_id"
        else
            echo "  ✗ Token exists but doesn't work"
        fi
    else
        echo "  ✗ No token available"
    fi
    
    echo "=== End Diagnostics ==="
}

# Try to load cached metadata first
if ! ec2_load_cached_metadata; then
    echo "EC2 metadata library loaded successfully"
    echo "Available functions: ec2_init_metadata, ec2_get_metadata, ec2_diagnose"
    echo "Call ec2_init_metadata to retrieve instance information"
else
    echo "EC2 metadata library loaded with cached data"
fi
