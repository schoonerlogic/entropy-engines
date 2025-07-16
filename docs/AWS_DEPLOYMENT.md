# AWS Deployment Guide

This guide provides step-by-step instructions for deploying the Entropy Engines platform on AWS.

## Prerequisites

### AWS Account Setup
- AWS account with administrative access
- AWS CLI configured with appropriate credentials
- SSH key pair created in your target AWS region
- Service limits checked for required instance types

### Local Tools
- Terraform >= 1.0.0
- AWS CLI >= 2.0
- kubectl (for cluster access)
- ssh client

### Required IAM Permissions
Your AWS user/role needs these permissions:
- EC2 full access (instances, VPC, security groups, IAM roles)
- S3 access (for state backend if using remote state)
- CloudWatch access (for monitoring)

## Quick Start

### 1. Configure AWS CLI
```bash
aws configure
# Enter your Access Key ID, Secret Access Key, region, and output format
```

### 2. Clone and Setup
```bash
git clone <repository-url>
cd entropy-engines
cp terraform.tfvars.example terraform.tfvars
```

### 3. Edit Configuration
Edit `terraform.tfvars` with your specific settings:

```hcl
# Required
cluster_name   = "my-agentic-platform"
environment    = "dev"
aws_region     = "us-east-1"
ssh_key_name   = "your-existing-keypair"

# Optional - customize as needed
control_plane_count       = 3
control_plane_instance_type = "t3.medium"
cpu_worker_count         = 2
cpu_worker_instance_type = "m7g.large"
gpu_worker_count         = 1
gpu_worker_instance_type = "g5g.xlarge"
```

### 4. Deploy
```bash
# Initialize Terraform
terraform init

# Plan deployment
./deploy.sh plan

# Apply deployment
./deploy.sh apply
```

### 5. Access Cluster
```bash
# Get kubeconfig
./scripts/get-kubeconfig.sh

# Verify cluster
kubectl get nodes
kubectl get pods -A
```

## Detailed Configuration

### AWS Regions and AZs
```hcl
aws_region         = "us-west-2"
availability_zones  = ["us-west-2a", "us-west-2b", "us-west-2c"]
```

### Instance Type Recommendations

#### Control Plane
- **Development**: `t3.medium` (2 vCPU, 4 GB RAM)
- **Production**: `t3.large` or `m5.large` (2 vCPU, 8 GB RAM)

#### CPU Workers
- **General Purpose**: `m7g.large` (2 vCPU, 8 GB RAM, ARM64)
- **Compute Optimized**: `c7g.large` (2 vCPU, 4 GB RAM, ARM64)
- **x86_64 Alternative**: `m5.large` (2 vCPU, 8 GB RAM)

#### GPU Workers
- **Entry Level**: `g5g.xlarge` (4 vCPU, 16 GB RAM, NVIDIA T4G)
- **Mid-Range**: `g5g.2xlarge` (8 vCPU, 32 GB RAM, NVIDIA T4G)
- **High Performance**: `p3.2xlarge` (8 vCPU, 61 GB RAM, NVIDIA V100)

### Network Configuration
```hcl
# VPC Configuration
vpc_cidr = "10.0.0.0/16"

# Kubernetes Networking
pod_cidr     = "10.244.0.0/16"
service_cidr = "10.96.0.0/12"
```

### Security Configuration
```hcl
# SSH Access - restrict to your IP ranges
ssh_allowed_cidrs = ["10.0.0.0/8", "172.16.0.0/12"]

# Enable encryption
enable_volume_encryption = true
```

## Cost Optimization

### Development Environment
```hcl
# Use single NAT gateway for cost savings
single_nat_gateway = true

# Use smaller instances
control_plane_instance_type = "t3.small"
cpu_worker_instance_type = "t3.medium"

# Reduce node count
control_plane_count = 1
cpu_worker_count = 1
gpu_worker_count = 0
```

### Production Environment
```hcl
# High availability NAT
single_nat_gateway = false

# Larger instances
control_plane_instance_type = "t3.large"
cpu_worker_instance_type = "m7g.xlarge"

# Full redundancy
control_plane_count = 3
cpu_worker_count = 3
gpu_worker_count = 2
```

## Advanced Features

### Spot Instances
Enable spot instances for cost savings:
```hcl
use_spot_instances = true
spot_price = "0.10"
```

### VPC Endpoints
Enable VPC endpoints to reduce data transfer costs:
```hcl
enable_vpc_endpoints = true
```

### Custom AMI
Use custom Ubuntu AMI:
```hcl
ami_id = "ami-0abcdef1234567890"
```

## Monitoring and Logging

### CloudWatch Integration
- All instances send logs to CloudWatch
- Metrics are available in CloudWatch Metrics
- Set up alarms for critical metrics

### Accessing Logs
```bash
# View system logs
aws logs tail /aws/ec2/system --follow

# View Kubernetes logs
kubectl logs -n kube-system <pod-name>
```

## Security Best Practices

### Network Security
- All nodes in private subnets
- Bastion host for SSH access
- Security groups with least privilege
- VPC flow logs enabled

### IAM Security
- Instance roles with minimal permissions
- No hardcoded credentials
- Regular rotation of access keys

### Encryption
- EBS encryption enabled by default
- TLS for all communications
- Secrets encrypted at rest

## Troubleshooting

### Common Issues

#### 1. Insufficient Instance Quota
```bash
# Check service quotas
aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A
```

#### 2. VPC Limits
```bash
# Check VPC limits
aws service-quotas get-service-quota --service-code vpc --quota-code L-F678F1CE
```

#### 3. IAM Permissions
```bash
# Test IAM permissions
aws sts get-caller-identity
```

### Debug Commands
```bash
# Check AWS resources
aws ec2 describe-instances --filters "Name=tag:Cluster,Values=my-agentic-platform"

# Check security groups
aws ec2 describe-security-groups --filters "Name=tag:Cluster,Values=my-agentic-platform"

# Check IAM roles
aws iam list-roles --query 'Roles[?contains(RoleName, `my-agentic-platform`)]'
```

## Cleanup

### Destroy Infrastructure
```bash
# Destroy all resources
./deploy.sh destroy

# Verify cleanup
aws ec2 describe-instances --filters "Name=tag:Cluster,Values=my-agentic-platform"
```

### Manual Cleanup
If destroy fails:
```bash
# Delete instances manually
aws ec2 terminate-instances --instance-ids <instance-ids>

# Delete VPC
aws ec2 delete-vpc --vpc-id <vpc-id>
```

## Support

For AWS-specific issues:
- Check AWS Service Health Dashboard
- Review CloudWatch logs
- Verify IAM permissions
- Check service quotas