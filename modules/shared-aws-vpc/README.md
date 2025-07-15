# Enhanced AWS VPC Module

A security-hardened, cloud-agnostic AWS VPC module designed for Kubernetes deployments with support for CPU and GPU workloads.

## 🚀 Features

### ✅ Security Enhancements
- **Ubuntu 22.04 LTS** instead of 20.04
- **EBS encryption** enabled by default
- **Restricted SSH access** (no more 0.0.0.0/0)
- **Least-privilege IAM policies**
- **Enhanced security group rules**

### ✅ Cloud-Agnostic Design
- **Configurable CIDR blocks** for VPC and Kubernetes
- **Flexible subnet counts** (no longer hardcoded)
- **Architecture support** (arm64/x86_64)
- **Environment-based configuration**

### ✅ Kubernetes Integration
- **Cloud Controller Manager** IAM roles
- **GPU node support** with dedicated security groups
- **NATS messaging** security groups
- **Kubernetes-specific tagging**
- **EBS CSI driver** support

### ✅ Cost Optimization
- **Spot instance support** with dedicated IAM roles
- **S3 Gateway VPC endpoints** for cost savings
- **Single NAT gateway** option
- **VPC endpoints** for AWS services

## 📋 Usage

### Basic Usage

```hcl
module "vpc" {
  source = "./shared-module-aws-vpc"

  project      = "agentic-platform"
  environment  = "dev"
  vpc_name     = "agentic-vpc"
  aws_region   = "us-east-1"
  ssh_key_name = "my-key"
  
  # Security (recommended)
  ssh_allowed_cidrs    = ["10.0.0.0/8", "192.168.1.0/24"]
  bastion_allowed_cidrs = ["203.0.113.0/24"]
}
```

### Advanced Configuration

```hcl
module "vpc" {
  source = "./shared-module-aws-vpc"

  project      = "agentic-platform"
  environment  = "prod"
  vpc_name     = "agentic-prod-vpc"
  aws_region   = "us-west-2"
  ssh_key_name = "prod-key"

  # Network Configuration
  vpc_cidr              = "10.100.0.0/16"
  kubernetes_cidrs = {
    pod_cidr     = "10.200.0.0/16"
    service_cidr = "10.96.0.0/12"
  }
  
  # Subnet Configuration
  public_subnet_count  = 3
  private_subnet_count = 6
  availability_zones   = ["us-west-2a", "us-west-2b", "us-west-2c"]
  
  # Security
  ssh_allowed_cidrs     = ["10.0.0.0/8"]
  bastion_allowed_cidrs = ["203.0.113.0/24"]
  
  # Features
  enable_nats_messaging = true
  enable_gpu_nodes      = true
  enable_vpc_endpoints  = true
  enable_volume_encryption = true
  
  # Cost Optimization
  nat_type            = "gateway"
  single_nat_gateway  = false
}
```

## 🔧 Variables

### Core Configuration
| Variable | Description | Default |
|----------|-------------|---------|
| `project` | Project name for resource naming | `"agentic-platform"` |
| `environment` | Environment (dev/staging/prod) | `"dev"` |
| `vpc_name` | Name of the VPC | - |
| `aws_region` | AWS region | `"us-east-1"` |

### Network Configuration
| Variable | Description | Default |
|----------|-------------|---------|
| `vpc_cidr` | VPC CIDR block | `"10.0.0.0/16"` |
| `kubernetes_cidrs` | Kubernetes networking CIDRs | See variables.tf |
| `public_subnet_count` | Number of public subnets | `2` |
| `private_subnet_count` | Number of private subnets | `3` |
| `availability_zones` | List of AZs to use | Auto-discovered |

### Security Configuration
| Variable | Description | Default |
|----------|-------------|---------|
| `ssh_allowed_cidrs` | Allowed SSH CIDR blocks | `[]` |
| `bastion_allowed_cidrs` | Allowed bastion CIDR blocks | `[]` |
| `enable_bastion_host` | Create bastion host | `true` |
| `enable_volume_encryption` | EBS encryption | `true` |

### Kubernetes Features
| Variable | Description | Default |
|----------|-------------|---------|
| `enable_kubernetes_tags` | Add K8s tags to subnets | `true` |
| `enable_nats_messaging` | NATS security groups | `true` |
| `enable_gpu_nodes` | GPU node security groups | `true` |
| `nats_ports` | NATS messaging ports | See variables.tf |

### Cost Optimization
| Variable | Description | Default |
|----------|-------------|---------|
| `nat_type` | NAT type (gateway/instance/none) | `"gateway"` |
| `single_nat_gateway` | Use single NAT gateway | `true` |
| `enable_vpc_endpoints` | Enable VPC endpoints | `true` |

## 🏗️ Architecture

### Security Groups Created
- **Control Plane**: Kubernetes API, etcd communication
- **Worker Nodes**: Kubelet, NodePort services
- **GPU Nodes**: GPU-specific rules (extends worker)
- **NATS Messaging**: Client, cluster, and monitoring ports
- **Bastion**: SSH access with restricted CIDRs
- **VPC Endpoints**: AWS service access

### IAM Roles Created
- **Control Plane**: Full Kubernetes + CCM permissions
- **Worker Nodes**: Standard node permissions
- **GPU Workers**: Worker + GPU-specific permissions
- **Cloud Controller Manager**: AWS CCM permissions
- **Spot Fleet**: Spot instance management

## 🔄 Migration Guide

### From Legacy Configuration

#### 1. Update Variables
```hcl
# OLD
variable "bastion_cidr" {
  default = "0.0.0.0/0"
}

# NEW
variable "ssh_allowed_cidrs" {
  type    = list(string)
  default = ["10.0.0.0/8"]  # Specify your CIDRs
}
```

#### 2. Update AMI Selection
```hcl
# OLD
filter {
  name   = "name"
  values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
}

# NEW (automatic with variables)
variable "ubuntu_version" {
  default = "22.04"
}
variable "instance_ami_architecture" {
  default = "arm64"
}
```

#### 3. Update Network Configuration
```hcl
# OLD (hardcoded)
locals {
  vpc_cidr_block = "10.0.0.0/16"
  pod_cidr_block = "10.100.0.0/16"
}

# NEW (configurable)
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}
variable "kubernetes_cidrs" {
  default = {
    pod_cidr     = "10.244.0.0/16"
    service_cidr = "10.96.0.0/12"
  }
}
```

### Breaking Changes

1. **SSH Access**: Now requires explicit CIDR blocks
2. **AMI**: Updated to Ubuntu 22.04 LTS
3. **Security Groups**: New structure with dedicated roles
4. **IAM Roles**: Enhanced with specific permissions

### Backward Compatibility
- Legacy variables are still supported with warnings
- Old security group names are maintained
- Existing state can be migrated with minimal changes

## 📊 Outputs

### Network Outputs
- `vpc_id` - VPC ID
- `public_subnet_ids` - Public subnet IDs
- `private_subnet_ids` - Private subnet IDs
- `vpc_cidr_block` - VPC CIDR
- `cluster_dns_ip` - Kubernetes DNS IP

### Security Outputs
- `control_plane_security_group_id`
- `worker_nodes_security_group_id`
- `gpu_nodes_security_group_id`
- `nats_security_group_id`
- `bastion_security_group_id`

### IAM Outputs
- `control_plane_instance_profile_name`
- `worker_instance_profile_name`
- `gpu_worker_instance_profile_name`
- `spot_fleet_role_arn`

## 🧪 Testing

### Validate Configuration
```bash
terraform init
terraform validate
terraform plan
```

### Security Scan
```bash
# Check for security issues
tfsec .
```

## 📝 Examples

### Minimal Configuration
```hcl
module "vpc" {
  source = "./shared-module-aws-vpc"
  
  project      = "my-app"
  vpc_name     = "my-vpc"
  ssh_key_name = "my-key"
  ssh_allowed_cidrs = ["10.0.0.0/8"]
}
```

### Production Configuration
```hcl
module "vpc" {
  source = "./shared-module-aws-vpc"
  
  project      = "production-app"
  environment  = "prod"
  vpc_name     = "prod-vpc"
  aws_region   = "us-west-2"
  ssh_key_name = "prod-key"
  
  vpc_cidr = "10.50.0.0/16"
  kubernetes_cidrs = {
    pod_cidr     = "10.200.0.0/16"
    service_cidr = "10.96.0.0/12"
  }
  
  public_subnet_count  = 3
  private_subnet_count = 6
  
  ssh_allowed_cidrs     = ["10.50.0.0/16"]
  bastion_allowed_cidrs = ["203.0.113.0/24"]
  
  enable_volume_encryption = true
  kms_key_id              = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
}
```

## 🔗 Integration

This module is designed to work seamlessly with:
- **Cloud-agnostic Kubernetes modules** in `/modules/cloud-agnostic/`
- **Agent node deployment** scripts
- **NATS messaging** infrastructure
- **GPU workload** support

## 📞 Support

For issues or questions:
1. Check the migration guide above
2. Review the variable documentation
3. Test with `terraform plan` before applying
4. Use the provided examples as starting points