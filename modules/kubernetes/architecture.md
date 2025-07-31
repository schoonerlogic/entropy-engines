# Kubernetes Setup Architecture

## File Structure in S3
```
s3://your-bucket/scripts/
├── 00-shared-functions.sh       # Shared functions library
├── k8s-setup-main.sh           # Main orchestrator
├── 01-install-user-and-tooling.sh
├── 02-install-kubernetes.sh  
└── 03-install-cni.sh
```

## Execution Flow

### 1. Cloud-Init (User Data)
```bash
#!/bin/bash
# This goes in your Launch Template user_data

# Download the entrypoint script
aws s3 cp s3://your-bucket/scripts/entrypoint.sh /tmp/entrypoint.sh
chmod +x /tmp/entrypoint.sh

# Execute the entrypoint
/tmp/entrypoint.sh
```

### 2. Entrypoint Script
- ✅ Validates network connectivity (IMDSv2)
- ✅ Installs AWS CLI if needed
- ✅ Downloads all scripts from S3
- ✅ Validates required files exist
- ✅ Calls main orchestrator script

### 3. Main Orchestrator (k8s-setup-main.sh)
- ✅ Sources shared functions
- ✅ Performs one-time system preparation
- ✅ Executes scripts in defined order
- ✅ Handles errors and cleanup

### 4. Individual Scripts (01, 02, 03, 04)
- ✅ Source shared functions if needed
- ✅ Use shared functions for apt operations
- ✅ Focus on their specific tasks
- ✅ Consistent logging and error handling

## Benefits

### 🔧 Maintainability
- Single place to modify apt handling logic
- Clear separation of concerns
- Easy to add/remove setup steps

### 🛡️ Reliability  
- Robust network and apt lock handling
- Consistent error handling
- Comprehensive logging

### 🐛 Debuggability
- All logs in `/var/log/terraform-provisioning/`
- Scripts preserved on failure
- System state captured on errors

### ⚡ Performance
- One-time system preparation
- Efficient retry strategies
- No redundant operations

## Integration Points

### Terraform Variables
```hcl
# Pass these to your template
templatefile("entrypoint.sh.tftpl", {
  s3_bucket_name = var.script_bucket_name
})

templatefile("01-install-user-and-tooling.sh.tftpl", {
  k8s_user = var.kubernetes_user
  k8s_major_minor_stream = var.k8s_version
  k8s_package_version_string = var.k8s_package_version
})
```

### Launch Template User Data
```bash
#!/bin/bash
aws s3 cp s3://your-bucket/scripts/entrypoint.sh /tmp/entrypoint.sh
chmod +x /tmp/entrypoint.sh
/tmp/entrypoint.sh
```
