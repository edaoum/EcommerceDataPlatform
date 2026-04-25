# =============================================================================
# modules/ebs/main.tf
# Persistent EBS data volume for the data platform.
#
# This volume stores:
#   - Raw Kafka events (JSON, written by the Spark consumer)
#   - Processed datasets (Parquet, output of ETL jobs)
#   - Pipeline logs (Airflow task logs, Spark event logs)
#
# Volume type: gp3 — better throughput/IOPS than gp2 at the same cost.
# The volume is formatted and mounted by scripts/mount_ebs.sh after first deploy.
#
# ⚠️  AWS constraint: the EBS volume must be in the same Availability Zone
#     as the EC2 instance it is attached to. The AZ is passed from the EC2
#     module output in app/main.tf.
# =============================================================================

resource "aws_ebs_volume" "data_storage" {
  availability_zone = var.availability_zone
  size              = var.storage_size_gb
  type              = "gp3"

  # gp3 baseline: 3000 IOPS and 125 MB/s — sufficient for most data workloads.
  # Increase these values if Spark jobs are I/O-bound on this volume.
  # iops       = 3000   # max 16000
  # throughput = 125    # MB/s, max 1000

  tags = {
    Name        = "${var.project}-${var.env}-data-volume"
    Project     = var.project
    Environment = var.env
    ManagedBy   = "Terraform"
    Purpose     = "Raw events, processed datasets, and pipeline logs"
  }
}
