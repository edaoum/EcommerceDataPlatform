# =============================================================================
# modules/sg/main.tf
# Security Group for the Data Platform node.
#
# Opens the inbound ports required by every data-engineering tool in the stack.
# All outbound traffic is allowed so the node can pull packages and datasets.
#
# ⚠️  Production note: replace cidr_blocks = ["0.0.0.0/0"] with your VPN or
#     office IP range to restrict access.
# =============================================================================

resource "aws_security_group" "data_platform_sg" {
  name        = "${var.project}-${var.env}-sg"
  description = "Data Platform security group — exposes ports for data-engineering tools."

  # ── SSH ────────────────────────────────────────────────────────────────────
  # Required for Terraform remote-exec provisioning and manual maintenance.
  ingress {
    description      = "SSH — pipeline management and Terraform provisioning"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # ── HTTP ───────────────────────────────────────────────────────────────────
  # Used by Nginx as a reverse proxy entry point for web UIs.
  ingress {
    description      = "HTTP — Nginx reverse proxy"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # ── HTTPS ──────────────────────────────────────────────────────────────────
  ingress {
    description      = "HTTPS — secure web access"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # ── Apache Spark UI ────────────────────────────────────────────────────────
  # Available while a SparkContext or SparkSession is active.
  ingress {
    description      = "Apache Spark Web UI"
    from_port        = 4040
    to_port          = 4040
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # ── PostgreSQL ─────────────────────────────────────────────────────────────
  # Stores KPIs, aggregated metrics, and Airflow metadata.
  ingress {
    description      = "PostgreSQL — KPI storage and Airflow metadata DB"
    from_port        = 5432
    to_port          = 5432
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # ── Apache Airflow ─────────────────────────────────────────────────────────
  # Web UI for scheduling, triggering, and monitoring pipeline DAGs.
  ingress {
    description      = "Apache Airflow Web UI"
    from_port        = 8080
    to_port          = 8080
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # ── JupyterLab ─────────────────────────────────────────────────────────────
  # Interactive notebook environment for data exploration and ad-hoc analysis.
  ingress {
    description      = "JupyterLab — interactive data exploration"
    from_port        = 8888
    to_port          = 8888
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # ── Apache Kafka ───────────────────────────────────────────────────────────
  # Broker port for producers (data/producer.py) and Spark Structured Streaming.
  ingress {
    description      = "Apache Kafka broker"
    from_port        = 9092
    to_port          = 9092
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # ── Egress ─────────────────────────────────────────────────────────────────
  # Allow all outbound traffic: apt updates, pip installs, S3 dataset download.
  egress {
    description      = "All outbound traffic — package installs and data egress"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name        = "${var.project}-${var.env}-sg"
    Project     = var.project
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}
