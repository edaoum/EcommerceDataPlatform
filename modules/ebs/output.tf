# =============================================================================
# modules/ebs/output.tf
# =============================================================================

output "volume_id" {
  description = "AWS ID of the EBS data volume — used for aws_volume_attachment in app/main.tf."
  value       = aws_ebs_volume.data_storage.id
}

output "volume_az" {
  description = "Availability Zone of the data volume."
  value       = aws_ebs_volume.data_storage.availability_zone
}
