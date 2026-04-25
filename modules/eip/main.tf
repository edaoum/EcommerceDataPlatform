# =============================================================================
# modules/eip/main.tf
# Allocates an Elastic IP (static public IP) for the data platform node.
#
# Without a static IP, the node's public address changes every time it is
# stopped and restarted, breaking bookmarked UI URLs and SSH host entries.
# The EIP is associated with the EC2 instance in app/main.tf.
# =============================================================================

resource "aws_eip" "data_platform_eip" {
  # "vpc" domain is required for EIPs used inside a VPC (all modern AWS accounts).
  domain = "vpc"

  tags = {
    Name        = "${var.project}-${var.env}-eip"
    Project     = var.project
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}
