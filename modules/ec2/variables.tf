# =============================================================================
# modules/ec2/variables.tf
# =============================================================================

variable "project" {
  type        = string
  description = "Project name — used as a prefix in instance name and tags."
  default     = "data-platform"
}

variable "env" {
  type        = string
  description = "Deployment environment (dev, staging, prod)."
  default     = "dev"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type. Minimum t3.medium for Spark + Airflow."
  default     = "t3.medium"
}

variable "ssh_key_name" {
  type        = string
  description = "Name of the AWS EC2 key pair for SSH access."
  default     = "data-platform-key"
}

variable "private_key_path" {
  type        = string
  description = "Local filesystem path to the .pem private key for remote-exec provisioning."
}

variable "sg_name" {
  type        = string
  description = "Name of the security group to attach to this instance (from module.sg.sg_name)."
}

variable "public_ip" {
  type        = string
  description = "Elastic IP address — used by local-exec to log the node's address."
  default     = "pending"
}

variable "ssh_user" {
  type        = string
  description = "OS user for SSH provisioning. Default is 'ubuntu' for Ubuntu AMIs."
  default     = "ubuntu"
}
