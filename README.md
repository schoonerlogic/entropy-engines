# Entropy Engines - Cloud-Agnostic Agentic Platform

A **multi-agent, model-serving platform** built on **self-managed Kubernetes** with **cloud-agnostic infrastructure**, supporting both CPU and GPU workloads with low-latency inter-agent messaging.

## 🚀 Quick Start

### Prerequisites
- Terraform >= 1.0.0
- AWS CLI configured (for AWS deployments)
- SSH key pair in your target cloud

### Deploy in 3 Steps

1. **Configure**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your settings
   ```

2. **Deploy**
   ```bash
   ./deploy.sh aws apply
   ```

3. **Access**
   ```bash
   # Get kubeconfig
   ./scripts/get-kubeconfig.sh
   kubectl get nodes
   ```

## 🏗️ Architecture

### **Cloud-Agnostic Design**
- **Self-managed Kubernetes** with kubeadm
- **Modular infrastructure** supporting AWS, GCP, Azure
- **GPU/CPU workload separation** with proper taints
- **NATS messaging** for low-latency inter-agent communication

### **Core Components**
```
entropy-engines/
├── modules/
│   ├── cloud-agnostic/          # Cloud-agnostic modules
│   │   ├── kubernetes-cluster/  # kubeadm-based K8s setup
│   │   ├── agent-nodes/         # CPU/GPU worker nodes
│   │   └── nats-messaging/      # NATS cluster setup
│   ├── cloud-specific/          # Cloud-specific implementations
│   │   ├── aws/                 # AWS-specific resources
│   │   ├── gcp/                 # GCP-specific resources
│   │   └── azure/               # Azure-specific resources
│   └── shared/                  # Shared utilities
│       ├── networking/          # Generic networking
│       └── storage/             # Generic storage
├── modules/shared-aws-vpc/      # Enhanced AWS VPC module
├── infrastructure.tf            # Main orchestration
├── deploy.sh                    # Deployment script
└── terraform.tfvars.example     # Configuration template
```

## 🎯 Features

### **Security-First**
- **Ubuntu 22.04 LTS** across all nodes
- **EBS encryption** enabled by default
- **Restricted SSH access** with CIDR blocks
- **Least-privilege IAM policies**
- **Enhanced security group rules**

### **Cost Optimized**
- **Spot instance support** for cost savings
- **VPC endpoints** to reduce data transfer costs
- **Single NAT gateway** option for dev environments
- **Auto-scaling** capabilities

### **Kubernetes-Native**
- **Cloud Controller Manager** integration
- **GPU node support** with NVIDIA drivers
- **NATS messaging** cluster for agent communication
- **EBS CSI driver** for persistent storage
- **Calico CNI** for networking

## 🔧 Configuration

### **Basic Configuration**
```hcl
# terraform.tfvars
cloud_provider = "aws"
cluster_name   = "agentic-platform"
environment    = "dev"
aws_region     = "us-east-1"

# Security (REQUIRED)
ssh_key_name       = "your-key"
ssh_allowed_cidrs  = ["10.0.0.0/8", "192.168.1.0/24"]

# Node Configuration
control_plane_count       = 3
control_plane_instance_type = "t3.medium"
cpu_worker_count         = 2
cpu_worker_instance_type = "m7g.large"
gpu_worker_count         = 1
gpu_worker_instance_type = "g5g.xlarge"
```

### **Advanced Configuration**
```hcl
# Network customization
vpc_cidr = "10.100.0.0/16"
kubernetes_cidrs = {
  pod_cidr     = "10.200.0.0/16"
  service_cidr = "10.96.0.0/12"
}

# Security hardening
enable_volume_encryption = true
kms_key_id = "arn:aws:kms:..."

# Cost optimization
nat_type = "gateway"
single_nat_gateway = true
enable_vpc_endpoints = true
```

## 🚀 Deployment

### **Supported Clouds**
- **AWS** (fully supported)
- **GCP** (planned)
- **Azure** (planned)

### **Deployment Commands**
```bash
# Plan deployment
./deploy.sh aws plan

# Apply deployment
./deploy.sh aws apply

# Destroy infrastructure
./deploy.sh aws destroy
```

### **Access Your Cluster**
```bash
# Get cluster information
./scripts/cluster-info.sh

# SSH to control plane
./scripts/ssh-control-plane.sh

# Get kubeconfig
./scripts/get-kubeconfig.sh
```

## 📊 Monitoring & Observability

### **Built-in Monitoring**
- **Node exporter** daemonsets
- **DCGM exporter** for GPU metrics
- **Prometheus federation** support
- **CloudWatch integration** (AWS)

### **Health Checks**
```bash
# Check cluster health
kubectl get nodes
kubectl get pods -A

# Check NATS cluster
kubectl get pods -l app=nats -n messaging
```

## 🔍 Troubleshooting

### **Common Issues**
1. **SSH Access Denied**: Check `ssh_allowed_cidrs` configuration
2. **IAM Permissions**: Verify IAM roles and policies
3. **Network Issues**: Check security group rules
4. **GPU Detection**: Verify GPU node labels and taints

### **Debug Commands**
```bash
# Check VPC configuration
aws ec2 describe-vpcs --filters "Name=tag:Project,Values=agentic-platform"

# Check security groups
aws ec2 describe-security-groups --filters "Name=tag:Project,Values=agentic-platform"

# Check IAM roles
aws iam list-roles --query 'Roles[?contains(RoleName, `agentic-platform`)]'
```

## 🧪 Development

### **Local Testing**
```bash
# Validate configuration
terraform validate

# Format code
terraform fmt -recursive

# Security scan
tfsec .
```

### **Contributing**
1. Fork the repository
2. Create feature branch
3. Test with `terraform plan`
4. Submit pull request

## 📚 Documentation

- **[Architecture Guide](AGENTS.md)** - Detailed architecture documentation
- **[Deployment Guide](docs/DEPLOYMENT.md)** - Step-by-step deployment
- **[Security Guide](docs/SECURITY.md)** - Security best practices
- **[Migration Guide](modules/shared-aws-vpc/MIGRATION.md)** - From legacy VPC module

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/your-org/entropy-engines/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-org/entropy-engines/discussions)
- **Documentation**: [Wiki](https://github.com/your-org/entropy-engines/wiki)

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Terraform AWS Modules** for VPC foundation
- **Kubernetes community** for kubeadm patterns
- **NATS.io** for messaging infrastructure