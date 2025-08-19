#!/bin/bash
# 01-install-user-and-tooling.sh.tftpl
# Refactored to use shared functions architecture
# Creates target user, installs Kubernetes components, and configures container runtime

# =================================================================
# SHARED FUNCTIONS INTEGRATION
# =================================================================

# Set DEBUG default to avoid unbound variable errors
DEBUG=0

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

setup_logging "install-user-and-tooling"

log_info "Starting K8s setup"

# System preparation check (let shared functions handle the logic)
if command -v prepare_system_once >/dev/null 2>&1; then
    prepare_system_once
else
    log_info "System already prepared, skipping preparation"
fi

# =================================================================
# CONFIGURATION VARIABLES (from Terraform)
# =================================================================
readonly K8S_KEYRING_DIR="/etc/apt/keyrings"
readonly K8S_KEYRING_FILE="${K8S_KEYRING_DIR}/kubernetes-apt-keyring.gpg"

log_info "=== User and Tooling Installation Started ==="
log_info "Target User: $K8S_USER"
log_info "K8S Repo Stream: $K8S_MAJOR_MINOR_STREAM"
log_info "K8S Package Version: $K8S_PACKAGE_VERSION_STRING"

# =================================================================
# INSTANCE METADATA RETRIEVAL
# =================================================================
source "${SCRIPT_DIR}/001-ec2-metadata-lib.sh"
ec2_init_metadata || exit 1

# =================================================================
# AWS CREDENTIALS VALIDATION
# =================================================================
validate_aws_credentials() {
    log_info "=== Validating AWS Credentials ==="
    
    # Check IAM role credentials
    if [ -n "$AWS_METADATA_TOKEN" ] 2>/dev/null; then
        log_info "IAM role credentials:"
        curl -s -H "X-aws-ec2-metadata-token: $AWS_METADATA_TOKEN" \
          "http://169.254.169.254/latest/meta-data/iam/security-credentials/" || {
            log_warn "Could not fetch IAM role info"
        }
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
# USER MANAGEMENT
# =================================================================
setup_target_user() {
    log_info "=== User Setup ==="
    
    # Create user if doesn't exist
    if ! id "$K8S_USER" &>/dev/null; then
        log_info "Creating user: $K8S_USER"
        if useradd -m -s /bin/bash "$K8S_USER"; then
            # Disable password authentication
            passwd -d "$K8S_USER"
            log_info "User $K8S_USER created successfully"
        else
            log_error "Failed to create user $K8S_USER"
            return 1
        fi
    else
        log_info "User $K8S_USER already exists"
    fi
    
    # Configure passwordless sudo
    local sudoers_file="/etc/sudoers.d/$K8S_USER"
    echo "$K8S_USER ALL=(ALL) NOPASSWD:ALL" > "$sudoers_file"
    chmod 440 "$sudoers_file"
    log_info "Passwordless sudo configured for $K8S_USER"
}

# =================================================================
# SSH KEY CONFIGURATION
# =================================================================
setup_ssh_keys() {
    log_info "=== SSH Key Setup ==="
    
    if [ -z "$EC2_METADATA_TOKEN" ] 2>/dev/null; then
        log_warn "No metadata token available for SSH key retrieval"
        return 1
    fi
    
    # Fetch SSH public key from metadata
    local ssh_key=""
    if ssh_key=$(curl -H "X-aws-ec2-metadata-token: $EC2_METADATA_TOKEN" \
                   -fsSL "http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key" \
                   --connect-timeout 10 --max-time 15 2>/dev/null); then
        
        if [ -n "$ssh_key" ] && [ "$ssh_key" != "Failed"* ]; then
            local user_ssh_dir="/home/$K8S_USER/.ssh"
            
            # Create SSH directory
            mkdir -p "$user_ssh_dir"
            
            # Write authorized_keys
            echo "$ssh_key" > "$user_ssh_dir/authorized_keys"
            
            # Set proper permissions
            chmod 700 "$user_ssh_dir"
            chmod 600 "$user_ssh_dir/authorized_keys"
            chown -R "$K8S_USER:$K8S_USER" "$user_ssh_dir"
            
            log_info "SSH key configured for $K8S_USER"
            return 0
        fi
    fi
    
    log_warn "Could not retrieve or configure SSH public key"
    return 1
}

# =================================================================
# SYSTEM CONFIGURATION
# =================================================================
configure_system_for_kubernetes() {
    log_info "=== System Configuration for Kubernetes ==="
    
    # Disable swap
    log_info "Disabling swap..."
    swapoff -a || {
        log_warn "Failed to disable swap (may already be disabled)"
    }
    
    # Comment out swap in fstab
    if [ -f /etc/fstab ]; then
        sed -i.bak '/ swap / s/^/#/' /etc/fstab
        log_info "Swap disabled in /etc/fstab"
    fi
    
    # Load required kernel modules
    log_info "Loading kernel modules..."
    modprobe overlay || log_warn "Failed to load overlay module"
    modprobe br_netfilter || log_warn "Failed to load br_netfilter module"
    
    # Persist kernel modules
    cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF
    log_info "Kernel modules configured"
    
    # Configure sysctl parameters
    log_info "Configuring sysctl parameters..."
    cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
    
    # Apply sysctl settings
    if sysctl --system >/dev/null 2>&1; then
        log_info "Sysctl parameters applied successfully"
    else
        log_warn "Some sysctl parameters may not have applied correctly"
    fi
}

# =================================================================
# KUBERNETES REPOSITORY SETUP
# =================================================================
setup_kubernetes_repository() {
    log_info "=== Kubernetes Repository Setup ==="
    
    # Create keyring directory
    mkdir -p "$K8S_KEYRING_DIR"
    
    # Download and install GPG key
    local key_url="https://pkgs.k8s.io/core:/stable:/v$K8S_MAJOR_MINOR_STREAM/deb/Release.key"
    log_info "Downloading Kubernetes GPG key for v$K8S_MAJOR_MINOR_STREAM..."
    
    if curl -fsSL "$key_url" | gpg --dearmor -o "$K8S_KEYRING_FILE"; then
        log_info "Kubernetes GPG key installed successfully"
    else
        log_error "Failed to download/install Kubernetes GPG key from $key_url"
        return 1
    fi
    
    # Add repository to sources
    local repo_entry="deb [signed-by=$K8S_KEYRING_FILE] https://pkgs.k8s.io/core:/stable:/v$K8S_MAJOR_MINOR_STREAM/deb/ /"
    echo "$repo_entry" > /etc/apt/sources.list.d/kubernetes.list
    log_info "Kubernetes repository added to sources"
    
    # Update package lists
    retry_apt "apt-get update"
}

# =================================================================
# PACKAGE INSTALLATION
# =================================================================
install_system_packages() {
    log_info "=== Installing System Packages ==="
    
    # Install basic dependencies
    local basic_packages="apt-transport-https ca-certificates curl gpg jq vim"
    install_packages $basic_packages
    
    log_info "Basic packages installed successfully"
}

install_kubernetes_packages() {
    log_info "=== Installing Kubernetes Packages ==="
    
    # Remove the conflicting package (add -y for non-interactive)
    log_info "Removing conflicting cnitool-plugins package..."
    apt-get remove -y cnitool-plugins || log_warn "cnitool-plugins not installed or removal failed"
    
    # Clean up any partial installations
    log_info "Configuring partially installed packages..."
    dpkg --configure -a
    
    log_info "Fixing broken dependencies..."
    apt-get -f install -y
    
    # Build package string directly (no arrays = no Terraform template conflicts)
    local k8s_package_list="kubelet=$K8S_PACKAGE_VERSION_STRING kubeadm=$K8S_PACKAGE_VERSION_STRING kubectl=$K8S_PACKAGE_VERSION_STRING"
    
    log_info "Installing: $k8s_package_list"
    
    if install_packages $k8s_package_list; then
        # Hold packages to prevent automatic updates
        log_info "Holding Kubernetes packages to prevent automatic updates..."
        apt-mark hold kubelet kubeadm kubectl
        log_info "Kubernetes packages installed and held successfully"
        
        # Enable kubelet service
        systemctl enable kubelet
        log_info "kubelet service enabled"
    else
        log_error "Failed to install Kubernetes packages"
        log_info "Available kubeadm versions:"
        apt-cache madison kubeadm 2>/dev/null || log_warn "Could not list available versions"
        return 1
    fi
}

install_container_runtime() {
    log_info "=== Installing and Configuring Container Runtime ==="
    
    # Install containerd
    install_packages "containerd"
    
    # Create config directory
    mkdir -p /etc/containerd
    
    # Generate default config if it doesn't exist
    if [ ! -f /etc/containerd/config.toml ]; then
        log_info "Generating default containerd configuration..."
        if containerd config default > /etc/containerd/config.toml; then
            log_info "Default containerd config generated"
        else
            log_error "Failed to generate default containerd config"
            return 1
        fi
    else
        log_info "Existing containerd config found, preserving it"
    fi
    
    # Ensure CRI plugin is enabled
    if grep -q 'disabled_plugins.*cri' /etc/containerd/config.toml; then
        log_info "Enabling CRI plugin..."
        sed -i 's/^disabled_plugins = \["cri"\]/#disabled_plugins = ["cri"]/' /etc/containerd/config.toml
    fi
    
    # Configure SystemdCgroup (critical for Kubernetes)
    log_info "Enabling SystemdCgroup..."
    sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/' /etc/containerd/config.toml
    
    # Restart containerd
    if manage_service "restart" "containerd"; then
        log_info "Containerd restarted successfully"
    else
        log_error "Failed to restart containerd"
        log_error "Debug info: journalctl -u containerd --no-pager -l"
        return 1
    fi
    
    # Verify containerd is working
    log_info "Verifying containerd functionality..."
    if timeout 15 bash -c 'until ctr version >/dev/null 2>&1; do sleep 1; done'; then
        log_info "Containerd is operational"
        
        # Show version for confirmation
        local containerd_version=""
        containerd_version=$(ctr version --format json 2>/dev/null | jq -r '.Server.Version' 2>/dev/null || echo "unknown")
        log_info "Containerd version: $containerd_version"
    else
        log_error "Containerd failed to become operational"
        # Show what's wrong
        ctr version 2>&1 | head -10 || true
        return 1
    fi
}

# =================================================================
# MAIN EXECUTION
# =================================================================
main() {
    log_info "Starting user and tooling installation..."
    
    # Get instance metadata
    if ! ec2_init_metadata; then
        log_error "Failed to retrieve instance metadata"
        return 1
    fi
    
    # Validate AWS credentials
    validate_aws_credentials
    
    # Set up target user
    if ! setup_target_user; then
        log_error "User setup failed"
        return 1
    fi
    
    # Configure SSH keys (non-fatal if it fails)
    setup_ssh_keys || log_warn "SSH key setup failed, continuing..."
    
    # Configure system for Kubernetes
    if ! configure_system_for_kubernetes; then
        log_error "System configuration failed"
        return 1
    fi
    
    # Install system packages
    if ! install_system_packages; then
        log_error "System package installation failed"
        return 1
    fi
    
    # Set up Kubernetes repository
    if ! setup_kubernetes_repository; then
        log_error "Kubernetes repository setup failed"
        return 1
    fi
    
    # Install Kubernetes packages
    if ! install_kubernetes_packages; then
        log_error "Kubernetes package installation failed"
        return 1
    fi
    
    # Install and configure container runtime
    if ! install_container_runtime; then
        log_error "Container runtime installation failed"
        return 1
    fi
    
    log_info "=== User and Tooling Installation Completed Successfully ==="
    log_info "Installed components:"
    log_info "- User: $K8S_USER (with sudo access)"
    log_info "- Kubernetes: $(kubectl version --client --output=yaml 2>/dev/null | grep gitVersion || echo 'version check failed')"
    log_info "- Containerd: $(ctr version --format json 2>/dev/null | jq -r '.Server.Version' || echo 'version check failed')"
    
    return 0
}

# Execute main function
main "$@"
