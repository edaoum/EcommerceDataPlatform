# =============================================================================
# modules/sg/output.tf
# =============================================================================

output "sg_name" {
  description = "Name of the data platform security group (used by the EC2 module)."
  value       = aws_security_group.data_platform_sg.name
}

output "sg_id" {
  description = "ID of the data platform security group."
  value       = aws_security_group.data_platform_sg.id
}
