# =============================================================================
# modules/sg/variables.tf
# =============================================================================

variable "project" {
  type        = string
  description = "Project name — used as a prefix in the security group name and tags."
  default     = "data-platform"
}

variable "env" {
  type        = string
  description = "Deployment environment (dev, staging, prod)."
  default     = "dev"
}
