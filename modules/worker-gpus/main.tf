# modules/gpu-workers/main.tf

locals {
  # --- S3 Bootstrap Script Location ---
  s3_bucket_id = var.worker_s3_bootstrap_bucket.id # Assuming this is just the bucket name
  # Path to your main bootstrap script template (the one that installs k8s, etc.)
  # This is the script that gets uploaded to S3.
  main_bootstrap_script = var.worker_gpu_bootstrap_script
  # Path to your loader script template (the one we just corrected above)
  loader_script_template_path = "${path.module}/scripts/seed-gpu-node-init.sh" # Or your actual path

  # --- Variables for the MAIN script (instance-init-from-baked-ami.sh) ---
  # These are the actual values your main script needs.

  # Construct the full package version string for apt-get
  # e.g., if k8s_full_patch_version is "1.33.1" and k8s_apt_package_suffix is "-1.1", this becomes "1.33.1-1.1"
  # e.g., if k8s_full_patch_version is "1.33.1" and k8s_apt_package_suffix is "-00", this becomes "1.33.1-00"
  calculated_k8s_package_version_for_install = "${var.k8s_full_patch_version}${var.k8s_apt_package_suffix}"

  tf_main_script_target_user_val                = var.k8s_user
  tf_main_script_k8s_repo_stream_val            = var.k8s_major_minor_stream                       # e.g., "1.33"
  tf_main_script_k8s_package_version_string_val = local.calculated_k8s_package_version_for_install # Uses the combined value
  tf_main_script_ssm_join_command_path_val      = var.ssm_join_command_path
  # tf_main_script_cluster_dns_ip_val          = var.cluster_dns_ip # Optional, if used by main script as a 5th arg
  #

  # --- Variables for the LOADER script template (seed-gpu-node-init.sh) ---
  # The keys here (e.g., s3_uri_for_main_script_tf) MUST match the `${...}` placeholders
  # in your corrected loader script template (seed-gpu-node-init.sh).
  vars_for_loader_script_template = {
    s3_uri_for_main_script_tf = "s3://${local.s3_bucket_id}/${local.main_bootstrap_script[0].key}" # S3 URI of the main script

    # These map to the ARG1, ARG2, etc. that the loader script will pass to the main script
    main_script_arg1_target_user_tf            = local.tf_main_script_target_user_val
    main_script_arg2_k8s_repo_stream_tf        = local.tf_main_script_k8s_repo_stream_val
    main_script_arg3_k8s_pkg_version_string_tf = local.tf_main_script_k8s_package_version_string_val # Correctly mapped
    main_script_arg4_ssm_join_command_path_tf  = local.tf_main_script_ssm_join_command_path_val      # Correctly mapped
    # main_script_arg5_cluster_dns_ip_tf           = local.tf_main_script_cluster_dns_ip_val           # Optional
  }

  # This renders your loader_script_template_path with vars_for_loader_script_template
  worker_user_data = var.use_base_ami ? null : base64encode(templatefile(local.loader_script_template_path, local.vars_for_loader_script_template))

  # ... rest of your locals ...
  # Ensure worker_tag_key, worker_tag_value, effective_spot_instance_types, etc., are still correctly defined.
  worker_tag_key                = "ClusterWorkerType"
  worker_tag_value              = "${var.cluster_name}-gpu-worker"
  effective_spot_instance_types = coalescelist(var.spot_instance_types, [var.instance_type])
  data_volume_size_gb           = 101
  data_volume_type              = "gp3"
  data_volume_device_name       = "/dev/sdf"
}


# Uploads the large script file (gpu-node-init.sh) to S3
resource "aws_s3_object" "worker_script" {
  bucket = local.s3_bucket_id # Use bucket name from variable/var
  key    = local.main_bootstrap_script[0].key
  source = local.main_bootstrap_script[0].source

  # Ensure Terraform replaces the object if the file content changes
  etag = filemd5(local.main_bootstrap_script[0].source)

  # Optional: Set content type for clarity
  content_type = "text/x-shellscript"

  tags = {
    Name   = "worker-gpu-bootstrap-script-${var.cluster_name}"
    Script = basename(local.main_bootstrap_script[0].source)
  }
}


#  ---  On-Demand Instances  ---
resource "aws_instance" "worker_gpu" {
  count = (var.gpu_on_demand_count + var.gpu_spot_count) > 0 ? 1 : 0

  ami           = var.base_ami_id
  instance_type = var.instance_type
  key_name      = var.ssh_key_name
  subnet_id     = element(var.subnet_ids, tonumber(count.index) % length(var.subnet_ids))

  iam_instance_profile   = var.iam_instance_profile_name
  vpc_security_group_ids = var.security_group_ids

  # Standard root block device configuration (adjust size as needed)
  root_block_device {
    volume_size           = var.root_volume_size_gb # Assuming you have a var for root volume size, e.g., 50
    volume_type           = var.root_volume_type    # Assuming you have a var, e.g., "gp3"
    delete_on_termination = true
  }

  # Attach the additional EBS volume for data/models
  ebs_block_device {
    device_name           = local.data_volume_device_name
    volume_type           = local.data_volume_type
    volume_size           = local.data_volume_size_gb
    delete_on_termination = true
    # encrypted             = true # Optional: enable encryption
    tags = {
      Name = "${var.cluster_name}-gpu-worker-${count.index}-data-vol"
    }
  }

  tags = {
    Name                      = "${var.cluster_name}-gpu-worker-${count.index}"
    "${local.worker_tag_key}" = local.worker_tag_value
    Cluster                   = var.cluster_name
  }

  user_data = local.worker_user_data
}

#  ---   Spot Fleet Requests  ---

# Create Launch Template for Spot Fleet
resource "aws_launch_template" "gpu_worker_lt" {
  count = (var.gpu_on_demand_count + var.gpu_spot_count) > 0 ? 1 : 0

  name_prefix = "${var.cluster_name}-gpu-worker-lt-"
  description = "Launch template for ${var.cluster_name} GPU worker Spot Fleet"
  image_id    = var.base_ami_id
  key_name    = var.ssh_key_name

  iam_instance_profile {
    name = var.iam_instance_profile_name
  }
  vpc_security_group_ids = var.security_group_ids
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
      Name = "${var.cluster_name}-gpu-worker-fleet"
      # Add the common tag for data source filtering
      "${local.worker_tag_key}" = local.worker_tag_value
      Cluster                   = var.cluster_name

      IamPolicyVersion = var.iam_policy_version
    }
  }
  #  Tag volumes
  tag_specifications {
    resource_type = "volume"
    tags = {
      Name    = "${var.cluster_name}-gpu-worker-volume"
      Cluster = var.cluster_name
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "gpu_worker_asg" {
  count = (var.gpu_on_demand_count + var.gpu_spot_count) > 0 ? 1 : 0

  name_prefix      = "${var.cluster_name}-cpu-worker-asg"
  desired_capacity = var.instance_count
  min_size         = var.instance_count # Or a lower value if you allow scaling down
  max_size         = var.instance_count # Or a higher value if you want to allow scaling up

  # Specify all the subnets where instances can be launched
  vpc_zone_identifier = var.subnet_ids

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
