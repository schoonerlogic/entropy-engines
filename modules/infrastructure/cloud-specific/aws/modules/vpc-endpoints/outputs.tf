
output "s3_endpoint_id" {
  value = aws_vpc_endpoint.s3.id
}
#
# output "ecr_api_endpoint_id" {
#   value = aws_vpc_endpoint.ecr_api[0].id
# }
#
# output "ecr_dkr_endpoint_id" {
#   value = aws_vpc_endpoint.ecr_dkr[0].id
# }
#
# output "sts_endpoint_id" {
#   value = aws_vpc_endpoint.sts[0].id
# }
#
# output "ec2_endpoint_id" {
#   value = aws_vpc_endpoint.ec2[0].id
# }
#
# output "logs_endpoint_id" {
#   value = aws_vpc_endpoint.logs[0].id
# }
#
# output "elasticloadbalancing_endpoint_id" {
#   value = aws_vpc_endpoint.elasticloadbalancing[0].id
# }
#
# # modules/vpc-endpoints/outputs.tf
# output "vpc_endpoints" {
#   value = {
#     s3                   = aws_vpc_endpoint.s3.id
#     ecr_api              = aws_vpc_endpoint.ecr_api[0].id
#     ecr_dkr              = aws_vpc_endpoint.ecr_dkr[0].id
#     sts                  = aws_vpc_endpoint.sts[0].id
#     ec2                  = aws_vpc_endpoint.ec2[0].id
#     logs                 = aws_vpc_endpoint.logs[0].id
#     elasticloadbalancing = aws_vpc_endpoint.elasticloadbalancing[0].id
#   }
#   description = "Map of created VPC endpoint IDs"
# }
