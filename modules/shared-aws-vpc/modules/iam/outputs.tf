# modules/iam/outputs.tf

output "ec2_role_arn" {
  description = "The ARN of the general EC2 IAM role."
  value       = aws_iam_role.ec2_role.arn
}

output "ec2_role_name" {
  description = "The name of the general EC2 IAM role."
  value       = aws_iam_role.ec2_role.name
}

output "ec2_instance_profile_arn" {
  description = "The ARN of the EC2 instance profile."
  value       = aws_iam_instance_profile.ec2_profile.arn
}

output "ec2_instance_profile_name" {
  description = "The name of the EC2 instance profile."
  value       = aws_iam_instance_profile.ec2_profile.name
}

output "ec2_instance_connect_policy_arn" {
  description = "The ARN of the IAM policy for EC2 Instance Connect."
  value       = aws_iam_policy.ec2_instance_connect.arn
}

output "spot_fleet_role_arn" {
  description = "The ARN of the IAM role for the EC2 Spot Fleet service."
  value       = aws_iam_role.spot_fleet_role.arn
}

output "spot_fleet_role_name" {
  description = "The name of the IAM role for the EC2 Spot Fleet service."
  value       = aws_iam_role.spot_fleet_role.name
}

# output "tooling_role_arn" {
#   description = "The ARN of the IAM role for tooling instances."
#   value       = aws_iam_role.tooling_role.arn
# }
#
# output "tooling_role_name" {
#   description = "The name of the IAM role for tooling instances."
#   value       = aws_iam_role.tooling_role.name
# }
#
# output "tooling_instance_profile_arn" {
#   description = "The ARN of the instance profile for tooling instances."
#   value       = aws_iam_instance_profile.tooling_profile.arn
# }
#
# output "tooling_instance_profile_name" {
#   description = "The name of the instance profile for tooling instances."
#   value       = aws_iam_instance_profile.tooling_profile.name
# }

