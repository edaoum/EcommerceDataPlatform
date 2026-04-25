# =============================================================================
# modules/ebs/variables.tf
# =============================================================================

variable "project" {
  type        = string
  description = "Project name — used as a prefix in the volume name tag."
  default     = "data-platform"
}

variable "env" {
  type        = string
  description = "Deployment environment (dev, staging, prod)."
  default     = "dev"
}

variable "availability_zone" {
  type        = string
  description = <<-EOT
    AWS Availability Zone for the EBS volume.
    Must match the EC2 instance AZ exactly — passed from module.ec2.availability_zone.
  EOT
  default     = "us-east-1a"
}

variable "storage_size_gb" {
  type        = number
  description = "EBS volume size in GB. 50 GB for dev, 200+ GB for production."
  default     = 50
}
