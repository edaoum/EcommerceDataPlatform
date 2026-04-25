# =============================================================================
# app/main.tf
# Entry point for the Data Platform infrastructure.
#
# This file orchestrates all Terraform modules to deploy a full data engineering
# stack on AWS: a compute node (EC2), persistent storage (EBS), a static public
# IP (EIP), and a pre-configured security group exposing data-tool ports.
#
# Usage:
#   terraform init
#   terraform plan
#   terraform apply
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Provider
# Reads AWS credentials from a local file (for local dev).
# In production, prefer an IAM role attached to the EC2 instance.
# -----------------------------------------------------------------------------
provider "aws" {
  region                   = var.aws_region
  shared_credentials_files = ["../credentials/aws_credentials.txt"]
}

# -----------------------------------------------------------------------------
# Module: Security Group
# Opens inbound ports required by data-engineering tools:
#   22   → SSH
#   80   → HTTP (Nginx reverse proxy)
#   443  → HTTPS
#   4040 → Apache Spark UI
#   5432 → PostgreSQL
#   8080 → Apache Airflow UI
#   8888 → JupyterLab
#   9092 → Apache Kafka broker
# -----------------------------------------------------------------------------
module "sg" {
  source  = "../modules/sg"
  project = var.project
  env     = var.env
}

# -----------------------------------------------------------------------------
# Module: Elastic IP
# Allocates a static public IP so the node's address never changes across
# stop/start cycles, ensuring stable URLs for all web UIs.
# -----------------------------------------------------------------------------
module "eip" {
  source  = "../modules/eip"
  project = var.project
  env     = var.env
}

# -----------------------------------------------------------------------------
# Module: EC2 — Data Platform Node
# Provisions an Ubuntu 22.04 LTS instance and bootstraps the toolchain via
# remote-exec: Kafka, Spark, Airflow, JupyterLab, PostgreSQL, Nginx, Java 11.
# -----------------------------------------------------------------------------
module "ec2" {
  source           = "../modules/ec2"
  project          = var.project
  env              = var.env
  instance_type    = var.instance_type
  ssh_key_name     = var.ssh_key_name
  private_key_path = "${path.root}/../credentials/data-platform.pem"
  sg_name          = module.sg.sg_name
  public_ip        = module.eip.public_ip
}

# -----------------------------------------------------------------------------
# Module: EBS — Persistent Data Volume
# A dedicated gp3 volume for raw events, pipeline logs, and processed datasets.
# Must be in the same Availability Zone as the EC2 instance (AWS constraint).
# -----------------------------------------------------------------------------
module "ebs" {
  source            = "../modules/ebs"
  project           = var.project
  env               = var.env
  availability_zone = module.ec2.availability_zone
  storage_size_gb   = var.data_volume_size_gb
}

# -----------------------------------------------------------------------------
# Associations
# These resources connect the modules together after they are created.
# They are defined here (not inside modules) to avoid circular dependencies.
# -----------------------------------------------------------------------------

# Attach the Elastic IP to the EC2 instance.
resource "aws_eip_association" "eip_assoc" {
  instance_id   = module.ec2.instance_id
  allocation_id = module.eip.allocation_id
}

# Attach the EBS data volume to the EC2 instance at /dev/sdf.
# On Ubuntu, the OS will expose this as /dev/xvdf or /dev/nvme1n1.
# Run scripts/mount_ebs.sh after first deploy to format and mount it.
resource "aws_volume_attachment" "data_volume_attachment" {
  device_name  = "/dev/sdf"
  volume_id    = module.ebs.volume_id
  instance_id  = module.ec2.instance_id
  force_detach = false
}
