# =============================================================================
# modules/ec2/output.tf
# =============================================================================

output "instance_id" {
  description = "AWS ID of the data platform EC2 instance — used for EIP and EBS associations."
  value       = aws_instance.data_platform_node.id
}

output "availability_zone" {
  description = "AZ of the EC2 instance — passed to the EBS module so the volume is co-located."
  value       = aws_instance.data_platform_node.availability_zone
}

output "private_ip" {
  description = "Private IP of the node, for VPC-internal service communication."
  value       = aws_instance.data_platform_node.private_ip
}
