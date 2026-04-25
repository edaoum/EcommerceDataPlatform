# =============================================================================
# app/variables.tf
# All configurable deployment parameters for the Data Platform.
#
# Override any variable at apply time:
#   terraform apply -var="env=prod" -var="instance_type=t3.large"
# =============================================================================

variable "project" {
  type        = string
  description = "Project name used as a prefix for all AWS resource names and tags."
  default     = "data-platform"
}

variable "env" {
  type        = string
  description = "Deployment environment. Controls resource naming and tagging."
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.env)
    error_message = "env must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region where all resources will be provisioned."
  default     = "us-east-1"
}

variable "instance_type" {
  type        = string
  description = <<-EOT
    EC2 instance type for the data platform node.
    Minimum recommended: t3.medium (2 vCPU, 4 GB RAM) for Spark + Airflow.
    Use t3.large or m5.large for production workloads.
  EOT
  default     = "t3.medium"

  validation {
    condition = contains([
      "t3.medium", "t3.large", "t3.xlarge",
      "m5.large", "m5.xlarge",
      "r5.large", "r5.xlarge"
    ], var.instance_type)
    error_message = "Choose an instance type suited for data workloads (t3.medium or larger)."
  }
}

variable "ssh_key_name" {
  type        = string
  description = "Name of the AWS EC2 key pair used for SSH access to the node."
  default     = "data-platform-key"
}

variable "data_volume_size_gb" {
  type        = number
  description = <<-EOT
    Size of the EBS data volume in GB.
    This volume stores raw Kafka events, Spark outputs, and pipeline logs.
    50 GB is sufficient for development; use 200+ GB for production.
  EOT
  default     = 50

  validation {
    condition     = var.data_volume_size_gb >= 10 && var.data_volume_size_gb <= 1000
    error_message = "Data volume size must be between 10 GB and 1000 GB."
  }
}
