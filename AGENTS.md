# AGENTS.md – Cloud-Agnostic Agentic Platform
> Purpose: build a **multi-agent, model-serving platform** on self-managed Kubernetes with cloud-agnostic infrastructure, supporting both CPU and GPU workloads with low-latency messaging between agents.

---

## Build / Lint / Test
- `terraform init` – pull providers  
- `terraform validate` – syntax & schema  
- `terraform plan` – preview changes  
- `terraform fmt` – format (run pre-commit)  
- `terraform fmt -check` – CI gate  
- `tflint` – lint rules (`aws_instance_previous_type`, etc.)

---

## Code Style
- 2-space indentation in `.tf`  
- snake_case for variables, locals, resources  
- PascalCase for resource types  
- Add `description` to every variable & output  
- Provider pins: `~>` minor version  
- Terraform block: `required_version >= 1.0.0`  
- Use `locals` for complex expressions  
- Inline comments for non-obvious logic

## Terraform File Structure Best Practices
Following HashiCorp's standard module structure:

### File Organization
```
module/
├── main.tf          # Main resource configurations
├── variables.tf     # Input variable declarations  
├── outputs.tf       # Output value definitions
├── versions.tf      # Provider and Terraform version requirements
├── terraform.tfvars # Variable values (not committed)
└── README.md        # Module documentation
```

### File Purpose
- **main.tf**: Primary resource definitions and core logic
- **variables.tf**: All input variable declarations with descriptions, types, and defaults
- **outputs.tf**: All output definitions with descriptions
- **versions.tf**: Provider requirements and Terraform version constraints
- **terraform.tfvars**: Actual variable values (use .example for templates)

### Naming Conventions
- Use descriptive names for all resources
- Prefix variables with module context when needed
- Group related variables together with comments
- Include validation blocks for critical variables

---

## Error Handling
- Bash scripts: `set -euxo pipefail`  
- Bootstrap logs: `/var/log/agent-bootstrap.log` with `$(date -Iseconds)`  
- Terraform: wrap data lookups with `can()` / `try()`  
- Validate AMIs via SSM data source before create

---

## 🎯 North-Star Vision
We are standing up an **agentic compute mesh**:
- **CPU-only agents** (Ubuntu 22.04 ARM64/x86_64) run deterministic workflows.  
- **GPU agents** (NVIDIA/AMD/Intel) host on-device SLMs, diffusion, and GATs.  
- **Self-managed Kubernetes** with kubeadm for cloud portability.  
- **NATS/gRPC bus** provides zero-copy, low-latency inter-agent messaging.

---

## 🏗️ Cloud-Agnostic Architecture

### **Kubernetes Control Plane**
- **kubeadm-based** setup for cloud portability
- **HA configuration** with stacked etcd or external etcd
- **Cloud provider integrations** via CCM (Cloud Controller Manager)
- **Container Storage Interface (CSI)** for persistent volumes

### **Node Groups**
| Group | Purpose | Taints | Labels |
|-------|---------|--------|--------|
| `control-plane` | Kubernetes masters | `node-role.kubernetes.io/master:NoSchedule` | `node-role.kubernetes.io/master=` |
| `cpu-agents` | CPU-only workloads | `workload=cpu:NoSchedule` | `agent-type=cpu,kubernetes.io/arch=arm64` |
| `gpu-agents` | GPU workloads | `nvidia.com/gpu=true:NoSchedule` | `agent-type=gpu,accelerator=nvidia-tesla` |

### **Cloud-Specific vs Cloud-Agnostic**
| Component | Cloud-Specific | Cloud-Agnostic Alternative |
|-----------|----------------|---------------------------|
| **Instances** | AWS EC2, GCP Compute, Azure VM | Generic `cloud_instance` module |
| **Storage** | EBS, GCE PD, Azure Disk | CSI drivers with cloud-specific backends |
| **Load Balancer** | ELB, GLB, Azure LB | MetalLB or cloud-specific CCM |
| **Networking** | VPC, Subnets, Security Groups | Generic network module with cloud-specific implementations |
| **IAM** | AWS IAM, GCP IAM, Azure AD | Kubernetes RBAC + cloud-specific IRSA/OIDC |

---

## 🏗️ Terraform Module Structure
```
modules/
├── cloud-agnostic/          # Cloud-agnostic modules
│   ├── kubernetes-cluster/  # kubeadm-based K8s setup
│   ├── agent-nodes/         # CPU/GPU worker nodes
│   └── nats-messaging/      # NATS cluster setup
├── cloud-specific/          # Cloud-specific implementations
│   ├── aws/                 # AWS-specific resources
│   ├── gcp/                 # GCP-specific resources
│   └── azure/               # Azure-specific resources
└── shared/                  # Shared utilities
    ├── networking/          # Generic networking
    └── storage/             # Generic storage
```

---

## 🔄 Agent & Model Lifecycle
| Hook | Shell snippet |
|------|---------------|
| **Health Pulse** | `while true; do echo "$(date -Iseconds) alive" \| nats-pub agent.$HOSTNAME.heartbeat; sleep 10; done &` |
| **Model Warm-Up** | `python3 /opt/models/warmup.py --type=llama3-8b --device=gpu` |
| **Crash Handling** | Exit code `42` triggers K8s restart policy. |
| **Node Registration** | `kubeadm join --token <token> <master-ip>:6443 --discovery-token-ca-cert-hash sha256:<hash>` |

---

## Cloud-Specific Configuration Examples

### **AWS Configuration**
- **AMI Selection**: SSM `/aws/service/canonical/ubuntu/server/22.04/stable/current/arm64/hvm/ebs-gp2`
- **Instance Types**: `m7g.large` (CPU), `g5g.xlarge` (GPU)
- **Security Groups**: `sg-agent-comms` (TCP 4222, 7422), `sg-k8s-api` (6443)
- **Storage**: EBS with CSI driver
- **IAM**: IRSA for pod-level AWS access

### **GCP Configuration**
- **Image**: Ubuntu 22.04 LTS ARM64
- **Instance Types**: `t2a-standard-2` (CPU), `a2-highgpu-1g` (GPU)
- **Firewall Rules**: Allow NATS ports (4222, 7422), K8s API (6443)
- **Storage**: PD with CSI driver
- **IAM**: Workload Identity for pod-level GCP access

### **Azure Configuration**
- **Image**: Ubuntu 22.04 LTS ARM64
- **Instance Types**: `D2pls_v5` (CPU), `NC24ads_A100_v4` (GPU)
- **NSG Rules**: Allow NATS ports (4222, 7422), K8s API (6443)
- **Storage**: Managed Disks with CSI driver
- **IAM**: AAD Pod Identity for pod-level Azure access

---

## Observability
- **DaemonSets**: `node-exporter` + `dcgm-exporter`  
- **Prometheus federation scrape**  
- **Bootstrap logs**: Cloud-specific logging (CloudWatch, Stackdriver, Azure Monitor)
- **Metrics**: Kubernetes metrics server + custom agent metrics

---

## Cost Guardrails
- **Tagging**: `Project=AgenticPlatform`, `Owner=AI-Ops`, `Environment=dev/prod`
- **Resource Limits**: Use cloud-specific cost optimization tools
- **Auto-scaling**: Cluster Autoscaler for node scaling, HPA for pod scaling

---
