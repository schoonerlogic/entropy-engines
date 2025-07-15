# Migration Guide: Legacy to Enhanced AWS VPC Module

This guide helps migrate from the legacy AWS VPC module to the enhanced, security-hardened version.

## 🚨 Breaking Changes

### 1. SSH Access Security
**BEFORE**: SSH open to 0.0.0.0/0
```hcl
variable "bastion_allowed_ssh_cidrs" {
  default = ["0.0.0.0/0"]
}
```

**AFTER**: Explicit CIDR blocks required
```hcl
variable "ssh_allowed_cidrs" {
  type    = list(string)
  default = []  # Must specify your CIDRs
}

variable "bastion_allowed_cidrs" {
  type    = list(string)
  default = []
}
```

### 2. Ubuntu Version Update
**BEFORE**: Ubuntu 20.04
**AFTER**: Ubuntu 22.04 LTS (configurable)

### 3. Network Configuration
**BEFORE**: Hardcoded CIDRs
```hcl
locals {
  vpc_cidr_block     = "10.0.0.0/16"
  pod_cidr_block     = "10.100.0.0/16"
  service_cidr_block = "192.168.0.0/16"
}
```

**AFTER**: Configurable CIDRs
```hcl
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

## 🔄 Step-by-Step Migration

### Step 1: Backup Current State
```bash
# Backup your current state
cp terraform.tfstate terraform.tfstate.backup
cp terraform.tfvars terraform.tfvars.backup
```

### Step 2: Update Variables

#### Update terraform.tfvars
```hcl
# OLD
aws_region   = "us-east-1"
project      = "AstralMaris"
vpc_name     = "my-vpc"
ssh_key_name = "my-key"
bastion_cidr = "0.0.0.0/0"

# NEW
aws_region   = "us-east-1"
project      = "AstralMaris"
vpc_name     = "my-vpc"
ssh_key_name = "my-key"

# Security (REQUIRED)
ssh_allowed_cidrs    = ["10.0.0.0/8", "192.168.1.0/24"]
bastion_allowed_cidrs = ["203.0.113.0/24"]

# Optional enhancements
environment = "dev"
vpc_cidr = "10.0.0.0/16"
kubernetes_cidrs = {
  pod_cidr     = "10.244.0.0/16"
  service_cidr = "10.96.0.0/12"
}
```

### Step 3: Update Module Configuration

#### OLD main.tf
```hcl
module "network" {
  source = "./modules/network"

  project      = var.project
  nat_type     = var.nat_type
  bastion_type = var.bastion_type
  ssh_key_name = var.ssh_key_name
  vpc_name     = var.vpc_name
  region       = var.aws_region
}
```

#### NEW main.tf
```hcl
module "network" {
  source = "./modules/network"

  project      = var.project
  environment  = var.environment
  vpc_name     = var.vpc_name
  region       = var.aws_region
  ssh_key_name = var.ssh_key_name
  nat_type     = var.nat_type
  
  # Security
  ssh_allowed_cidrs    = var.ssh_allowed_cidrs
  bastion_allowed_cidrs = var.bastion_allowed_cidrs
  
  # Network
  vpc_cidr              = var.vpc_cidr
  kubernetes_cidrs      = var.kubernetes_cidrs
  
  # Features
  enable_nats_messaging = true
  enable_gpu_nodes      = true
  enable_vpc_endpoints  = true
}
```

### Step 4: Handle State Migration

#### Option A: State Refresh (Recommended)
```bash
# Refresh state to pick up new resources
terraform refresh

# Plan to see changes
terraform plan

# Apply if changes look correct
terraform apply
```

#### Option B: State Migration (Advanced)
```bash
# Import new resources if needed
terraform import module.vpc.aws_security_group.k8s_control_plane sg-xxxxxxxx
terraform import module.vpc.aws_security_group.k8s_nodes sg-yyyyyyyy
```

### Step 5: Update Outputs

#### OLD outputs.tf
```hcl
output "vpc_id" {
  value = module.network.vpc_id
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}
```

#### NEW outputs.tf
```hcl
output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "control_plane_security_group_id" {
  value = module.network.control_plane_security_group_id
}

output "worker_nodes_security_group_id" {
  value = module.network.worker_nodes_security_group_id
}

output "control_plane_instance_profile_name" {
  value = module.iam.control_plane_instance_profile_name
}

output "worker_instance_profile_name" {
  value = module.iam.worker_instance_profile_name
}
```

## 🧪 Testing Migration

### 1. Validate Configuration
```bash
terraform init
terraform validate
```

### 2. Plan Migration
```bash
terraform plan -out=migration.plan
```

### 3. Review Changes
Look for:
- New security groups
- Updated IAM roles
- New VPC endpoints
- Modified subnet tags

### 4. Apply Changes
```bash
terraform apply migration.plan
```

## 🛠️ Common Issues & Solutions

### Issue 1: SSH Access Denied
**Problem**: Cannot SSH to instances after migration
**Solution**: Ensure `ssh_allowed_cidrs` includes your IP
```bash
# Add your current IP
echo 'ssh_allowed_cidrs = ["'$(curl -s ifconfig.me)'/32"]' >> terraform.tfvars
```

### Issue 2: Security Group Conflicts
**Problem**: Security group name conflicts
**Solution**: Use unique project/environment names
```hcl
project = "my-app-prod"
environment = "prod"
```

### Issue 3: IAM Role Conflicts
**Problem**: IAM role already exists
**Solution**: Use unique names or import existing roles
```bash
terraform import aws_iam_role.control_plane_role my-app-prod-control-plane-role
```

### Issue 4: Subnet CIDR Changes
**Problem**: Subnet CIDRs changed
**Solution**: Use same CIDR configuration as before
```hcl
vpc_cidr = "10.0.0.0/16"
public_subnet_count = 2
private_subnet_count = 4
```

## 📊 Migration Checklist

### Pre-Migration
- [ ] Backup terraform state and variables
- [ ] Document current CIDR blocks
- [ ] Identify SSH access requirements
- [ ] Test in non-production environment

### During Migration
- [ ] Update variables with new structure
- [ ] Add required CIDR blocks
- [ ] Update module configuration
- [ ] Run terraform plan
- [ ] Review all changes

### Post-Migration
- [ ] Verify SSH access works
- [ ] Check security group rules
- [ ] Validate IAM roles
- [ ] Test Kubernetes deployment
- [ ] Update documentation

## 🔍 Verification Commands

### Check Security Groups
```bash
aws ec2 describe-security-groups --filters "Name=group-name,Values=*-control-plane-*" --query 'SecurityGroups[].GroupId'
```

### Check IAM Roles
```bash
aws iam list-roles --query 'Roles[?contains(RoleName, `agentic-platform`)].RoleName'
```

### Check Subnets
```bash
aws ec2 describe-subnets --filters "Name=tag:Project,Values=agentic-platform" --query 'Subnets[].SubnetId'
```

## 🆘 Rollback Plan

If migration fails:

1. **Restore state backup**
```bash
cp terraform.tfstate.backup terraform.tfstate
cp terraform.tfvars.backup terraform.tfvars
```

2. **Restore module**
```bash
git checkout HEAD~1 -- shared-module-aws-vpc/
```

3. **Re-apply old configuration**
```bash
terraform plan
terraform apply
```

## 📞 Support

For migration issues:
1. Check this guide for common solutions
2. Review terraform plan output carefully
3. Test in non-production first
4. Use terraform state commands for troubleshooting

## 🎯 Next Steps

After successful migration:
1. Update your Kubernetes deployment scripts
2. Configure new IAM roles
3. Test GPU node deployment
4. Set up NATS messaging
5. Enable VPC endpoints for cost optimization