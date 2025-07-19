# modules/gpu-workers/main.tf
locals {
  base_ami_id               = var.base_ami_id
  bootstrap_script          = var.bootstrap_script
  instance_type             = var.instance_config.instance_type
  on_demand_count           = var.instance_config.on_demand_count
  spot_count                = var.instance_config.spot_count
  instance_types            = var.instance_config.instance_types
  cluster_name              = var.kubernetes_config.cluster_name
  k8s_user                  = var.kubernetes_config.k8s_user
  k8s_major_minor_stream    = var.kubernetes_config.k8s_major_minor_stream
  k8s_full_patch_version    = var.kubernetes_config.k8s_full_patch_version
  k8s_apt_package_suffix    = var.kubernetes_config.k8s_apt_package_suffix
  ssm_join_command_path     = var.kubernetes_config.ssm_join_command_path
  cluster_dns_ip            = var.kubernetes_config.cluster_dns_ip
  iam_policy_version        = var.network_config.iam_policy_version
  iam_instance_profile_name = var.network_config.iam_instance_profile_name
  ssh_key_name              = var.security_config.ssh_key_name
  ssh_public_key_path       = var.security_config.ssh_public_key_path
  ssh_private_key_path      = var.security_config.ssh_private_key_path
  security_group_ids        = var.security_config.security_group_ids
  subnet_ids                = var.security_config.subnet_ids
  bastion_host              = var.security_config.bastion_host
  bastion_user              = var.security_config.bastion_user
  pod_cidr_block            = var.security_config.kubernetes_cidrs.pod_cidr
  service_cidr_block        = var.security_config.kubernetes_cidrs.service_cidr
}

locals {
  # --- S3 Bootstrap Script Location ---
  s3_bucket_id = local.worker_s3_bootstrap_bucket.id # Assuming this is just the bucket name
  # Path to your main bootstrap script template (the one that installs k8s, etc.)
  # This is the script that gets uploaded to S3.

  # Path to your loader script template (the one we just corrected above)
  loader_script_template_path = "${path.module}/scripts/seed-gpu-node-init.sh" # Or your actual path

  # --- localiables for the MAIN script (instance-init-from-baked-ami.sh) ---
  # These are the actual values your main script needs.

  # Construct the full package version string for apt-get
  # e.g., if k8s_full_patch_version is "1.33.1" and k8s_apt_package_suffix is "-1.1", this becomes "1.33.1-1.1"
  # e.g., if k8s_full_patch_version is "1.33.1" and k8s_apt_package_suffix is "-00", this becomes "1.33.1-00"
  calculated_k8s_package_version_for_install = "${local.k8s_full_patch_version}${local.k8s_apt_package_suffix}"

  tf_main_script_target_user_val                = local.k8s_user
  tf_main_script_k8s_repo_stream_val            = local.k8s_major_minor_stream                     # e.g., "1.33"
  tf_main_script_k8s_package_version_string_val = local.calculated_k8s_package_version_for_install # Uses the combined value
  tf_main_script_ssm_join_command_path_val      = local.ssm_join_command_path
  # tf_main_script_cluster_dns_ip_val          = local.cluster_dns_ip # Optional, if used by main script as a 5th arg
  #

  # --- localiables for the LOADER script template (seed-gpu-node-init.sh) ---
  # The keys here (e.g., s3_uri_for_main_script_tf) MUST match the `${...}` placeholders
  # in your corrected loader script template (seed-gpu-node-init.sh).
  locals_for_loader_script_template = {
    s3_uri_for_main_script_tf = "s3://${local.s3_bucket_id}/${local.main_bootstrap_script[0].key}" # S3 URI of the main script

    # These map to the ARG1, ARG2, etc. that the loader script will pass to the main script
    main_script_arg1_target_user_tf            = local.tf_main_script_target_user_val
    main_script_arg2_k8s_repo_stream_tf        = local.tf_main_script_k8s_repo_stream_val
    main_script_arg3_k8s_pkg_version_string_tf = local.tf_main_script_k8s_package_version_string_val # Correctly mapped
    main_script_arg4_ssm_join_command_path_tf  = local.tf_main_script_ssm_join_command_path_val      # Correctly mapped
    # main_script_arg5_cluster_dns_ip_tf           = local.tf_main_script_cluster_dns_ip_val           # Optional
  }

  # This renders your loader_script_template_path with locals_for_loader_script_template
  worker_user_data = base64encode(templatefile(local.loader_script_template_path, local.locals_for_loader_script_template))

  # ... rest of your locals ...
  # Ensure worker_tag_key, worker_tag_value, effective_spot_instance_types, etc., are still correctly defined.
  worker_tag_key                = "ClusterWorkerType"
  worker_tag_value              = "${local.cluster_name}-gpu-worker"
  effective_spot_instance_types = coalescelist(local.instance_types, [local.instance_type])
  data_volume_size_gb           = 101
  data_volume_type              = "gp3"
  data_volume_device_name       = "/dev/sdf"

  total_instance_count = local.on_demand_count + local.spot_count
}


# Uploads the large script file (gpu-node-init.sh) to S3
resource "aws_s3_object" "worker_script" {
  bucket = local.s3_bucket_id # Use bucket name from localiable/local
  key    = local.main_bootstrap_script[0].key
  source = local.main_bootstrap_script[0].source

  # Ensure Terraform replaces the object if the file content changes
  etag = filemd5(local.main_bootstrap_script[0].source)

  # Optional: Set content type for clarity
  content_type = "text/x-shellscript"

  tags = {
    Name   = "worker-gpu-bootstrap-script-${local.cluster_name}"
    Script = basename(local.main_bootstrap_script[0].source)
  }
}


#  ---  On-Demand Instances  ---
resource "aws_instance" "worker_gpu" {
  count = local.total_instance_count > 0 ? 1 : 0

  ami           = local.base_ami_id
  instance_type = local.instance_type
  key_name      = local.ssh_key_name
  subnet_id     = element(local.subnet_ids, tonumber(count.index) % length(local.subnet_ids))

  iam_instance_profile   = local.iam_instance_profile_name
  vpc_security_group_ids = local.security_group_ids

  # Standard root block device configuration (adjust size as needed)
  #  "root_block_device" {
  #   volume_size           = local.root_volume_size_gb # Assuming you have a local for root volume size, e.g., 50
  #   volume_type           = local.root_volume_type    # Assuming you have a local, e.g., "gp3"
  #   delete_on_termination = true
  # }

  # Attach the additional EBS volume for data/models
  ebs_block_device {
    device_name           = local.data_volume_device_name
    volume_type           = local.data_volume_type
    volume_size           = local.data_volume_size_gb
    delete_on_termination = true
    # encrypted             = true # Optional: enable encryption
    tags = {
      Name = "${local.cluster_name}-gpu-worker-${count.index}-data-vol"
    }
  }

  tags = {
    Name                      = "${local.cluster_name}-gpu-worker-${count.index}"
    "${local.worker_tag_key}" = local.worker_tag_value
    Cluster                   = local.cluster_name
  }

  user_data = local.worker_user_data
}

#  ---   Spot Fleet Requests  ---

# Create Launch Template for Spot Fleet
resource "aws_launch_template" "gpu_worker_lt" {
  count = local.total_instance_count > 0 ? 1 : 0

  name_prefix = "${local.cluster_name}-gpu-worker-lt-"
  description = "Launch template for ${local.cluster_name} GPU worker Spot Fleet"
  image_id    = local.base_ami_id
  key_name    = local.ssh_key_name

  iam_instance_profile {
    name = local.iam_instance_profile_name
  }
  vpc_security_group_ids = local.security_group_ids
  user_data              = local.worker_user_data

  # Block device mappings for the launch template
  block_device_mappings {
    device_name = local.data_volume_device_name # e.g., "/dev/sdf"
    ebs {
      volume_type           = local.data_volume_type    # e.g., "gp3"
      volume_size           = local.data_volume_size_gb # e.g., 101
      delete_on_termination = true
    }
  }

  # Define tags that will be applied to instances launched by the fleet
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.cluster_name}-gpu-worker-fleet"
      # Add the common tag for data source filtering
      "${local.worker_tag_key}" = local.worker_tag_value
      Cluster                   = local.cluster_name

      IamPolicyVersion = local.iam_policy_version
    }
  }
  #  Tag volumes
  tag_specifications {
    resource_type = "volume"
    tags = {
      Name    = "${local.cluster_name}-gpu-worker-volume"
      Cluster = local.cluster_name
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "gpu_worker_asg" {
  count = local.total_instance_count > 0 ? 1 : 0

  name_prefix      = "${local.cluster_name}-cpu-worker-asg"
  desired_capacity = local.total_instance_count
  min_size         = local.total_instance_count # Or a lower value if you allow scaling down
  max_size         = local.total_instance_count # Or a higher value if you want to allow scaling up

  # Specify all the subnets where instances can be launched
  vpc_zone_identifier = local.subnet_ids

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.gpu_worker_lt[0].id
        version            = "$Latest"
      }

      dynamic "override" {
        for_each = local.effective_spot_instance_types
        content {
          instance_type = override.value
        }
      }
    }

    instances_distribution {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 0 # 0% On-Demand means 100% Spot
      spot_allocation_strategy                 = "capacity-optimized"
    }
  }
}



# --- Data Source to Fetch Worker Instance Details ---
# This fetches details AFTER instances are running and tagged,
# either from aws_instance or launched by the Spot Fleet.
data "aws_instances" "workers" {
  # Filter based on the common tag applied by both aws_instance and the launch template
  instance_tags = {
    "${local.worker_tag_key}" = local.worker_tag_value
  }

  # Filter based on instance state to avoid terminated instances
  instance_state_names = ["pending", "running"]

  # Make this data source depend on the creation path chosen
  # If using spot, depends on the fleet request fulfillment.
  # If not using spot, depends on the regular instance creation.
  depends_on = [
    aws_autoscaling_group.gpu_worker_asg
  ]
}

data "aws_instances" "worker_gpu_fleet_instances" {

  filter {
    name   = "tag:${local.worker_tag_key}"
    values = [local.worker_tag_value]
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }

  depends_on = [
    aws_autoscaling_group.gpu_worker_asg
  ]
}
