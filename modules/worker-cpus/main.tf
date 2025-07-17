# modules/cpu-workers/main.tf

locals {

  # --- S3 Bootstrap Script Location ---
  s3_bucket_id           = var.worker_s3_bootstrap_bucket.id
  main_script_var_path   = "${path.module}/templates/instance-init-from-baked-ami.sh.tftpl"
  loader_script_var_path = "${path.module}/scripts/seed-cpu-node-init.sh"
  # Include cluster name and hash in S3 key for organization and updates

  # Variables for the MAIN script (instance-init-from-baked-ami.sh.tpl)
  main_script_vars = {
    target_user           = var.k8s_user              # Passed to the main script
    ssm_join_command_path = var.ssm_join_command_path # Passed to the main script
    k8s_major_minor_arg   = var.k8s_major_minor_stream
    cluster_dns_ip        = var.cluster_dns_ip # For logging/info in main script (optional)
  }

  # Variables for the LOADER script (seed-cpu-node-init.sh)
  loader_script_vars = {
    s3_script_uri = "s3://${local.s3_bucket_id}/${var.worker_cpu_bootstrap_script[0].key}"
    # Arguments that the loader script will pass to the main script
    k8s_user_arg          = local.main_script_vars.target_user
    k8s_major_minor_arg   = local.main_script_vars.k8s_major_minor_arg
    ssm_join_command_path = local.main_script_vars.ssm_join_command_path
    cluster_dns_ip        = local.main_script_vars.cluster_dns_ip
  }

  worker_user_data = var.use_base_ami ? null : base64encode(templatefile(local.loader_script_var_path, local.loader_script_vars))
  #worker_user_data = base64encode(templatefile(local.loader_script_var_path, local.loader_script_vars))

  # --- Instance Identification (Updated Logic) ---
  # Tag used to identify instances launched by the spot fleet OR regular instances
  worker_tag_key   = "ClusterWorkerType"
  worker_tag_value = "${var.cluster_name}-cpu-worker"

  # Fetch details of instances (either regular or from Spot Fleet) using tags
  # This data source runs *after* the instances/fleet are created/fulfilled
  # Note: May need adjustment if instance creation is very slow or tags take time to apply.
  worker_instances_data = data.aws_instances.workers.ids
  worker_instances_ips  = data.aws_instances.workers.private_ips

  # Map details (assuming order is preserved, which is generally true for data sources)
  worker_details_map = {
    for i, id in local.worker_instances_data : i => {
      instance_id = id
      private_ip  = local.worker_instances_ips[i]
      # Note: The original index mapping (${count.index}) is lost with Spot Fleet tagging
      # erad
      # You could potentially add instance index as another tag if needed via user_data
    } if i < length(local.worker_instances_ips)
  }

  # --- Prepare list of instance types for Spot Fleet ---
  # Use the provided list, or default to a single type if the list is null/empty (optional fallback)
  effective_spot_instance_types = coalescelist(var.spot_instance_types, [var.instance_type])
}

# Uploads the large script file (cpu-node-init.sh) to S3
resource "aws_s3_object" "worker_script" {
  bucket = local.s3_bucket_id # Use bucket name from variable/var
  key    = var.worker_cpu_bootstrap_script[0].key
  source = local.main_script_var_path

  # Ensure Terraform replaces the object if the file content changes
  etag = filemd5(local.main_script_var_path)

  # Optional: Set content type for clarity
  content_type = "text/x-shellscript"

  tags = {
    Name   = "worker-cpu-bootstrap-script-${var.cluster_name}"
    Script = basename(local.main_script_var_path)
  }
}


#  ---  On-Demand Instances  ---
resource "aws_instance" "worker_cpu" {
  count = (var.cpu_on_demand_count + var.cpu_spot_count) > 0 ? 1 : 0

  ami           = var.base_ami_id
  instance_type = var.instance_type
  key_name      = var.ssh_key_name
  subnet_id     = element(var.subnet_ids, tonumber(count.index) % length(var.subnet_ids))

  iam_instance_profile   = var.iam_instance_profile_name
  vpc_security_group_ids = var.security_group_ids

  tags = {
    Name                      = "${var.cluster_name}-cpu-worker-${count.index}"
    "${local.worker_tag_key}" = local.worker_tag_value
    Cluster                   = var.cluster_name
  }

  user_data = local.worker_user_data
}

#  ---   Spot Fleet Requests  ---

# Create Launch Template for Spot Fleet
resource "aws_launch_template" "cpu_worker_lt" {
  name_prefix = "${var.cluster_name}-cpu-worker-lt"
  description = "Launch template for ${var.cluster_name} CPU worker Spot Fleet"
  image_id    = var.base_ami_id
  key_name    = var.ssh_key_name
  user_data   = local.worker_user_data

  iam_instance_profile {
    name = var.iam_instance_profile_name
  }

  vpc_security_group_ids = var.security_group_ids

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.cluster_name}-cpu-worker-fleet"
      # Add the common tag for data source filtering
      "${local.worker_tag_key}" = local.worker_tag_value
      Cluster                   = var.cluster_name
    }
  }
  #  Tag volumes
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "${var.cluster_name}-cpu-worker-volume"
      Cluster = var.cluster_name

      IamPolicyVersion = var.iam_policy_version
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "cpu_worker_asg" {
  count = (var.cpu_on_demand_count + var.cpu_spot_count) > 0 ? 1 : 0

  name_prefix      = "${var.cluster_name}-cpu-worker-asg"
  desired_capacity = var.instance_count
  min_size         = var.instance_count # Or a lower value if you allow scaling down
  max_size         = var.instance_count # Or a higher value if you want to allow scaling up

  # Specify all the subnets where instances can be launched
  vpc_zone_identifier = var.subnet_ids

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.cpu_worker_lt.id
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
    aws_autoscaling_group.cpu_worker_asg
  ]
}

data "aws_instances" "worker_cpu_fleet_instances" {

  filter {
    name   = "tag:${local.worker_tag_key}"
    values = [local.worker_tag_value]
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }

  depends_on = [
    aws_autoscaling_group.cpu_worker_asg
  ]
}
