# modules/iam/outputs.tf
# IAM module outputs

#===============================================================================
# General EC2 Role Outputs
#===============================================================================

output "ec2_role_arn" {
  description = "The ARN of the general EC2 IAM role"
  value       = aws_iam_role.ec2_role.arn
}

output "ec2_role_name" {
  description = "The name of the general EC2 IAM role"
  value       = aws_iam_role.ec2_role.name
}

output "ec2_instance_profile_arn" {
  description = "The ARN of the EC2 instance profile"
  value       = aws_iam_instance_profile.ec2_instance_profile.arn
}

output "ec2_instance_profile_name" {
  description = "The name of the EC2 instance profile"
  value       = aws_iam_instance_profile.ec2_instance_profile.name
}

#===============================================================================
# Control Plane Role Outputs
#===============================================================================

output "control_plane_role_arn" {
  description = "The ARN of the control plane IAM role"
  value       = aws_iam_role.control_plane_role.arn
}

output "control_plane_role_name" {
  description = "The name of the control plane IAM role"
  value       = aws_iam_role.control_plane_role.name
}

output "control_plane_role" {
  description = "Role name for use with k8s cloud control plane"
  value       = aws_iam_role.control_plane_role.name
}

output "control_plane_instance_profile_arn" {
  description = "The ARN of the control plane instance profile"
  value       = aws_iam_instance_profile.control_plane_instance_profile.arn
}

output "control_plane_instance_profile_name" {
  description = "The name of the control plane instance profile"
  value       = aws_iam_instance_profile.control_plane_instance_profile.name
}

#===============================================================================
# Worker Role Outputs
#===============================================================================

output "worker_role_arn" {
  description = "The ARN of the worker IAM role"
  value       = aws_iam_role.worker_role.arn
}

output "worker_role_name" {
  description = "The name of the worker IAM role"
  value       = aws_iam_role.worker_role.name
}

output "worker_instance_profile_arn" {
  description = "The ARN of the worker instance profile"
  value       = aws_iam_instance_profile.worker_instance_profile.arn
}

output "worker_instance_profile_name" {
  description = "The name of the worker instance profile"
  value       = aws_iam_instance_profile.worker_instance_profile.name
}

#===============================================================================
# GPU Worker Role Outputs
#===============================================================================

output "gpu_worker_role_arn" {
  description = "The ARN of the GPU worker IAM role"
  value       = aws_iam_role.gpu_worker_role.arn
}

output "gpu_worker_role_name" {
  description = "The name of the GPU worker IAM role"
  value       = aws_iam_role.gpu_worker_role.name
}

output "gpu_worker_instance_profile_arn" {
  description = "The ARN of the GPU worker instance profile"
  value       = aws_iam_instance_profile.gpu_worker_instance_profile.arn
}

output "gpu_worker_instance_profile_name" {
  description = "The name of the GPU worker instance profile"
  value       = aws_iam_instance_profile.gpu_worker_instance_profile.name
}

#===============================================================================
# Spot Fleet Role Outputs
#===============================================================================

output "spot_fleet_role_arn" {
  description = "The ARN of the IAM role for the EC2 Spot Fleet service"
  value       = aws_iam_role.spot_fleet_role.arn
}

output "spot_fleet_role_name" {
  description = "The name of the IAM role for the EC2 Spot Fleet service"
  value       = aws_iam_role.spot_fleet_role.name
}

#===============================================================================
# Policy Outputs
#===============================================================================

output "ec2_instance_connect_policy_arn" {
  description = "The ARN of the IAM policy for EC2 Instance Connect"
  value       = aws_iam_policy.ec2_instance_connect.arn
}

output "control_plane_policy_arn" {
  description = "The ARN of the control plane IAM policy"
  value       = aws_iam_policy.control_plane_policy.arn
}

output "worker_policy_arn" {
  description = "The ARN of the worker IAM policy"
  value       = aws_iam_policy.worker_policy.arn
}

output "gpu_worker_policy_arn" {
  description = "The ARN of the GPU worker IAM policy"
  value       = aws_iam_policy.gpu_worker_policy.arn
}
