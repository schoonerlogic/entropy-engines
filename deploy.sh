#!/bin/bash
set -euo pipefail

# AWS Agentic Platform Deployment Script
# Usage: ./deploy.sh [plan|apply|destroy]

ACTION=${1:-plan}
CLUSTER_NAME="agentic-platform"
ENVIRONMENT="dev"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        error "Terraform is not installed. Please install Terraform first."
    fi
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI first."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    log "Prerequisites check passed"
}

# Initialize Terraform
init_terraform() {
    log "Initializing Terraform..."
    terraform init -upgrade
    
    # Format and validate
    terraform fmt -recursive
    terraform validate
    
    log "Terraform initialization complete"
}

# Create SSH key if it doesn't exist
create_ssh_key() {
    local key_name="agentic-platform-key"
    local key_path="~/.ssh/${key_name}"
    
    if ! aws ec2 describe-key-pairs --key-names "$key_name" &> /dev/null; then
        log "Creating SSH key pair: $key_name"
        aws ec2 create-key-pair --key-name "$key_name" --query 'KeyMaterial' --output text > ~/.ssh/${key_name}.pem
        chmod 400 ~/.ssh/${key_name}.pem
        log "SSH key created: ~/.ssh/${key_name}.pem"
    else
        log "SSH key already exists: $key_name"
    fi
}

# Plan deployment
plan_deployment() {
    log "Planning deployment..."
    
    terraform plan \
        -var="cluster_name=$CLUSTER_NAME" \
        -var="environment=$ENVIRONMENT" \
        -out="tfplan"
}

# Apply deployment
apply_deployment() {
    log "Applying deployment..."
    
    if [[ -f "tfplan" ]]; then
        terraform apply "tfplan"
    else
        terraform apply \
            -var="cluster_name=$CLUSTER_NAME" \
            -var="environment=$ENVIRONMENT" \
            -auto-approve
    fi
    
    log "Deployment complete!"
    
    # Display cluster information
    display_cluster_info
}

# Destroy deployment
destroy_deployment() {
    warn "This will destroy all infrastructure. Are you sure? (yes/no)"
    read -r response
    if [[ "$response" != "yes" ]]; then
        log "Destruction cancelled"
        exit 0
    fi
    
    log "Destroying deployment..."
    terraform destroy \
        -var="cluster_name=$CLUSTER_NAME" \
        -var="environment=$ENVIRONMENT" \
        -auto-approve
    
    log "Destruction complete"
}

# Display cluster information
display_cluster_info() {
    log "Cluster Information:"
    echo "==================="
    echo "Cloud Provider: AWS"
    echo "Cluster Name: $CLUSTER_NAME"
    echo "Environment: $ENVIRONMENT"
    echo ""
    
    # Get outputs
    terraform output
}

# Main execution
main() {
    log "Starting deployment for AWS Agentic Platform"
    log "Action: $ACTION"
    
    check_prerequisites
    init_terraform
    
    case $ACTION in
        plan)
            create_ssh_key
            plan_deployment
            ;;
        apply)
            create_ssh_key
            apply_deployment
            ;;
        destroy)
            destroy_deployment
            ;;
        *)
            error "Invalid action: $ACTION. Use 'plan', 'apply', or 'destroy'"
            ;;
    esac
}

# Run main function
main "$@"