#!/bin/bash
# /tmp/k8s_scripts/00-shared-functions.sh
# Shared functions for all K8s setup scripts

# Global settings that all scripts should use
export DEBIAN_FRONTEND=noninteractive

# Global variables
SYSTEM_PREPARED=false

# Set default for DEBUG to avoid unbound variable errors
DEBUG=0

# =================================================================
# ENHANCED LOGGING SETUP WITH VERBOSITY CONTROL
# =================================================================

setup_logging() {
    # Configuration from environment or defaults - these are Terraform interpolated values
    # Set default if not provided by Terraform
    if [ -z "$LOG_LEVEL" ]; then
        LOG_LEVEL="INFO"
    fi
    local DEBUG_MODE="0"
    if [ -n "$DEBUG" ] 2>/dev/null; then
        DEBUG_MODE="$DEBUG"
    fi
    
    echo "Template variables received:"
    echo "LOG_DIR from Terraform: $LOG_DIR"
    echo "LOG_LEVEL from Terraform: $LOG_LEVEL"
    
    # Create log directory
    if ! mkdir -p "$LOG_DIR"; then
        echo "ERROR: Cannot create log directory: $LOG_DIR" >&2
        return 1
    fi
    chown "$(whoami):$(whoami)" "$LOG_DIR" 2>/dev/null || true
    
    # Auto-detect calling script name or use parameter
    local script_name
    if [ -n "$1" ]; then
        script_name="$1"
        echo "Using provided script name: $script_name"
    else
        # More robust detection - walk up BASH_SOURCE until we find non-shared-functions
        local found_caller=""
        for i in 1 2 3 4; do
            if [ -n "${BASH_SOURCE[$i]}" ]; then
                local candidate=""
                if [ -n "${BASH_SOURCE[$i]}" ]; then
                    candidate=$(basename "${BASH_SOURCE[$i]}")
                    candidate="${candidate%.sh}"
                    candidate="${candidate%.tftpl}"
                fi
                # Skip shared functions
                if [ "$candidate" != "00-shared-functions" ] && [ "$candidate" != "shared-functions" ]; then
                    found_caller="$candidate"
                    echo "Found caller at BASH_SOURCE[$i]: $found_caller"
                    break
                fi
            fi
        done
        
        if [ -n "$found_caller" ]; then
            script_name="$found_caller"
        else
            script_name="unknown-script"
        fi
        echo "Auto-detected script name: $script_name"
    fi
    
    echo "Final script_name: $script_name"
    
    # Setup log file paths
    full_log_path="$LOG_DIR/$script_name.log"
    error_log_path="$LOG_DIR/$script_name.log"
    debug_log_path="$LOG_DIR/$script_name.log"
    trace_log_path="$LOG_DIR/$script_name-trace.log"
    
    # Only set bash strict mode if not already set (to avoid conflicts)
    if ! echo "$-" | grep -q e; then
        set -euo pipefail
    fi
    
    # Export log paths for use by other functions
    export MAIN_LOG_PATH="$full_log_path"
    export ERROR_LOG_PATH="$error_log_path"
    export DEBUG_LOG_PATH="$debug_log_path"
    export TRACE_LOG_PATH="$trace_log_path"
    export LOG_LEVEL="$LOG_LEVEL"
     
    # Touch log files to ensure they exist
    touch "$full_log_path" "$error_log_path" 2>/dev/null || true
}

# Enhanced logging functions with level control
log_trace() {
    local message="[TRACE $(date '+%Y-%m-%d %H:%M:%S')] $*"
    if [ "$LOG_LEVEL" = "TRACE" ] 2>/dev/null; then
        if [ -n "$MAIN_LOG_PATH" ] 2>/dev/null; then
            echo "$message" | tee -a "$MAIN_LOG_PATH" >&2
        else
            echo "$message" >&2
        fi
    fi
}

log_debug() {
    local message="[DEBUG $(date '+%Y-%m-%d %H:%M:%S')] $*"
    if [ "$DEBUG" = "1" ] 2>/dev/null; then
        if [ -n "$MAIN_LOG_PATH" ] 2>/dev/null; then
            echo "$message" | tee -a "$MAIN_LOG_PATH" >&2
        else
            echo "$message" >&2
        fi
    fi
}

log_info() {
    local message="[INFO $(date '+%Y-%m-%d %H:%M:%S')] $*"
    # Only skip if explicitly set to ERROR mode
    if [ "$LOG_LEVEL" = "ERROR" ] 2>/dev/null; then
        return 0
    else
        if [ -n "$MAIN_LOG_PATH" ] 2>/dev/null; then
            echo "$message" | tee -a "$MAIN_LOG_PATH" >&2
        else
            echo "$message"
        fi
    fi
}

log_warn() {
    local message="[WARN $(date '+%Y-%m-%d %H:%M:%S')] $*"
    if [ -n "$MAIN_LOG_PATH" ] 2>/dev/null; then
        echo "$message" | tee -a "$MAIN_LOG_PATH" >&2
    else
        echo "$message" >&2
    fi
}

log_error() {
    local message="[ERROR $(date '+%Y-%m-%d %H:%M:%S')] $*"
    if [ -n "$MAIN_LOG_PATH" ] 2>/dev/null; then
        echo "$message" | tee -a "$MAIN_LOG_PATH" >&2
    else
        echo "$message" >&2
    fi
}

log_fatal() {
    local message="[FATAL $(date '+%Y-%m-%d %H:%M:%S')] $*"
    if [ -n "$MAIN_LOG_PATH" ] 2>/dev/null; then
        echo "$message" | tee -a "$MAIN_LOG_PATH" >&2
    else
        echo "$message" >&2
    fi
    exit 1
}

# Show current logging configuration (useful for debugging)
log_config_info() {
    echo "=== Logging Configuration ==="
    if [ -n "$LOG_LEVEL" ] 2>/dev/null; then
        echo "Log Level: $LOG_LEVEL"
    else
        echo "Log Level: INFO"
    fi
    if [ -n "$DEBUG" ] 2>/dev/null; then
        echo "Debug Mode: $DEBUG"
    else
        echo "Debug Mode: 0"
    fi
    if [ -n "$MAIN_LOG_PATH" ] 2>/dev/null; then
        echo "Main Log: $MAIN_LOG_PATH"
    else
        echo "Main Log: <not set>"
    fi
    if [ -n "$ERROR_LOG_PATH" ] 2>/dev/null; then
        echo "Error Log: $ERROR_LOG_PATH"
    else
        echo "Error Log: <not set>"
    fi
    echo "Bash Tracing: [status check would go here]"
    echo "=========================="
}

# Fixed system prepared file path to match what main script expects
SYSTEM_PREPARED_FILE="/tmp/.system_prepared"

# One-time system preparation (run only once across all scripts)
prepare_system_once() {
    if [ "$SYSTEM_PREPARED" = "true" ] || [ -f "$SYSTEM_PREPARED_FILE" ]; then
        log_info "System already prepared, skipping..."
        export SYSTEM_PREPARED="true"
        return 0
    fi
    
    log_info "=== One-time System Preparation ==="
    
    # Wait for system to settle
    log_info "Letting system settle..."
    sleep 30
    
    # Disable unattended-upgrades to prevent conflicts
    log_info "Disabling unattended-upgrades..."
    systemctl stop unattended-upgrades.service || true
    systemctl disable unattended-upgrades.service || true
    systemctl stop apt-daily.timer || true
    systemctl disable apt-daily.timer || true
    systemctl stop apt-daily-upgrade.timer || true
    systemctl disable apt-daily-upgrade.timer || true
    pkill -f unattended-upgrade || true
    sleep 5
    
    # Clear any stale locks
    rm -f /var/lib/apt/lists/lock || true
    rm -f /var/cache/apt/archives/lock || true
    rm -f /var/lib/dpkg/lock-frontend || true
    rm -f /var/lib/dpkg/lock || true
    
    # Initial apt update
    log_info "Initial apt update..."
    retry_apt "apt-get update"
    
    # Mark system as prepared
    SYSTEM_PREPARED=true
    
    # Mark system as prepared (persistent across scripts)
    touch "$SYSTEM_PREPARED_FILE"
    export SYSTEM_PREPARED="true"
    
    log_info "System preparation complete"
}

# Robust apt retry function
retry_apt() {
    local cmd="$*"
    local attempts=3
    local delay=15
    
    for i in $(seq 1 $attempts); do
        log_info "Executing: $cmd (attempt $i/$attempts)"
        
        # Quick lock check before each attempt
        if [ $i -gt 1 ]; then
            quick_apt_check || true
        fi
        
        if eval "$cmd"; then
            log_info "Command succeeded: $cmd"
            return 0
        fi
        
        if [ $i -lt $attempts ]; then
            log_warn "Command failed, retrying in $delay seconds..."
            sleep $delay
        fi
    done
    
    log_error "Command failed after $attempts attempts: $cmd"
    return 1
}

# Quick apt availability check
quick_apt_check() {
    local max_wait=60  # 1 minute
    local count=0
    
    while [ $count -lt $max_wait ]; do
        if ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 && \
           ! fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
            return 0
        fi
        
        log_info "Waiting for apt lock... ($count/$max_wait)"
        sleep 5
        count=$((count + 5))
    done
    
    log_warn "Apt lock check timeout, proceeding anyway"
    return 1
}

# Safe package installation wrapper
install_packages() {
    local packages="$*"
    log_info "Installing packages: $packages"
    retry_apt "apt-get install -y $packages"
}

# Safe service management
manage_service() {
    local action="$1"
    local service="$2"
    
    log_info "Service $action: $service"
    systemctl "$action" "$service" || {
        log_warn "Failed to $action $service, continuing..."
        return 1
    }
}

# Cleanup function (can be called at end of final script)
cleanup_system() {
    log_info "=== System Cleanup ==="
    
    # Re-enable unattended-upgrades if desired
    # systemctl enable unattended-upgrades.service || true
    # systemctl start unattended-upgrades.service || true
    
    log_info "Cleanup complete"
}

# Error handling
handle_error() {
    local line_number="$1"
    local error_code="$2"
    log_error "Script failed at line $line_number with exit code $error_code"
    log_error "Last command: $BASH_COMMAND"
    
    # Optional: Add cleanup or debugging info here
    log_error "Current apt processes:"
    ps aux | grep -E "(apt|dpkg|unattended)" | grep -v grep || true
}

# Set up error trap
trap 'handle_error ${LINENO} $?' ERR

# Initialize basic logging function for early use
# Note: Scripts should call setup_logging() to initialize full logging
if ! command -v log_info >/dev/null 2>&1; then
    log_info() {
        echo "[INFO $(date '+%Y-%m-%d %H:%M:%S')] $*"
    }
fi

echo "[INFO $(date '+%Y-%m-%d %H:%M:%S')] Shared functions loaded successfully (call setup_logging to initialize logging)"
