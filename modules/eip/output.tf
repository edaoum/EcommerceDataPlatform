# =============================================================================
# modules/eip/output.tf
# =============================================================================

output "public_ip" {
  description = "Static public IP address of the data platform node."
  value       = aws_eip.data_platform_eip.public_ip
}

output "allocation_id" {
  description = "Allocation ID of the Elastic IP — required for aws_eip_association in app/main.tf."
  value       = aws_eip.data_platform_eip.id
}
