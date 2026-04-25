# =============================================================================
# app/outputs.tf
# Values printed to the terminal after a successful `terraform apply`.
# Use these to quickly access the data platform's web interfaces.
# =============================================================================

output "data_platform_public_ip" {
  description = "Static public IP address of the data platform node (Elastic IP)."
  value       = module.eip.public_ip
}

output "data_platform_private_ip" {
  description = "Private IP of the node, for VPC-internal communication."
  value       = module.ec2.private_ip
}

output "data_volume_id" {
  description = "AWS ID of the attached EBS data storage volume."
  value       = module.ebs.volume_id
}

# ── Web UI URLs ──────────────────────────────────────────────────────────────

output "airflow_ui_url" {
  description = "Apache Airflow web UI — pipeline scheduling and monitoring."
  value       = "http://${module.eip.public_ip}:8080"
}

output "jupyter_ui_url" {
  description = "JupyterLab UI — interactive data exploration."
  value       = "http://${module.eip.public_ip}:8888"
}

output "spark_ui_url" {
  description = "Apache Spark UI — available when a Spark session is active."
  value       = "http://${module.eip.public_ip}:4040"
}
