# =============================================================================
# modules/ec2/main.tf
# Data Platform compute node — Ubuntu 22.04 LTS on EC2.
#
# The remote-exec provisioner bootstraps the full data engineering toolchain
# on first apply. This includes: Java 11, Python 3, Apache Kafka, Apache Spark,
# Apache Airflow, JupyterLab, PostgreSQL, and Nginx.
#
# Bootstrap duration: ~8–12 minutes on first apply.
# =============================================================================

# -----------------------------------------------------------------------------
# AMI lookup — always fetch the latest Ubuntu 22.04 LTS (Jammy Jellyfish).
# Owner 099720109477 is Canonical's official AWS account.
# -----------------------------------------------------------------------------
data "aws_ami" "ubuntu_lts" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# -----------------------------------------------------------------------------
# EC2 instance — the data platform node.
# -----------------------------------------------------------------------------
resource "aws_instance" "data_platform_node" {
  ami             = data.aws_ami.ubuntu_lts.id
  instance_type   = var.instance_type
  key_name        = var.ssh_key_name
  security_groups = [var.sg_name]

  # Root volume: 20 GB gp3 for the OS and installed tools.
  # Pipeline data goes on the separate EBS volume (modules/ebs).
  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name        = "${var.project}-${var.env}-node"
    Project     = var.project
    Environment = var.env
    ManagedBy   = "Terraform"
    Role        = "data-platform-node"
  }

  # ---------------------------------------------------------------------------
  # local-exec: Write the node's public IP to a local file for quick reference.
  # This runs on the Terraform host (your laptop), not the EC2 instance.
  # ---------------------------------------------------------------------------
  provisioner "local-exec" {
    command = "echo '[${var.project}/${var.env}] Node IP: ${var.public_ip}' >> ../data_platform_ips.txt"
  }

  # ---------------------------------------------------------------------------
  # remote-exec: Bootstrap the full data engineering toolchain.
  # Runs over SSH on the EC2 instance after it passes status checks.
  # ---------------------------------------------------------------------------
  provisioner "remote-exec" {
    inline = [
      # ── System update ───────────────────────────────────────────────────────
      "sudo apt-get update -y",
      "sudo apt-get upgrade -y",

      # ── Core dependencies ───────────────────────────────────────────────────
      # Java 11 is required by both Apache Kafka and Apache Spark.
      "sudo apt-get install -y python3 python3-pip python3-venv openjdk-11-jdk curl wget git unzip",

      # ── Apache Kafka ────────────────────────────────────────────────────────
      # Downloads and installs Kafka 3.6. Starts ZooKeeper then the broker.
      "wget -q https://downloads.apache.org/kafka/3.6.0/kafka_2.13-3.6.0.tgz -O /tmp/kafka.tgz",
      "tar -xzf /tmp/kafka.tgz -C /opt && ln -s /opt/kafka_2.13-3.6.0 /opt/kafka",
      "nohup /opt/kafka/bin/zookeeper-server-start.sh /opt/kafka/config/zookeeper.properties > /tmp/zookeeper.log 2>&1 &",
      "sleep 5",
      "nohup /opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties > /tmp/kafka.log 2>&1 &",
      "sleep 5",

      # Create Kafka topics for the e-commerce pipeline.
      "/opt/kafka/bin/kafka-topics.sh --create --topic user-events    --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1 || true",
      "/opt/kafka/bin/kafka-topics.sh --create --topic product-views  --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1 || true",
      "/opt/kafka/bin/kafka-topics.sh --create --topic ratings        --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1 || true",

      # ── Apache Spark ────────────────────────────────────────────────────────
      # Downloads Spark 3.5 (pre-built for Hadoop 3). No cluster setup needed
      # for single-node local mode used in this project.
      "wget -q https://downloads.apache.org/spark/spark-3.5.0/spark-3.5.0-bin-hadoop3.tgz -O /tmp/spark.tgz",
      "tar -xzf /tmp/spark.tgz -C /opt && ln -s /opt/spark-3.5.0-bin-hadoop3 /opt/spark",
      "echo 'export SPARK_HOME=/opt/spark' >> /home/ubuntu/.bashrc",
      "echo 'export PATH=$PATH:$SPARK_HOME/bin' >> /home/ubuntu/.bashrc",

      # ── Python data libraries ───────────────────────────────────────────────
      "pip3 install --upgrade pip",
      "pip3 install pandas pyarrow boto3 sqlalchemy psycopg2-binary kafka-python pyspark==3.5.0",

      # ── Apache Airflow ──────────────────────────────────────────────────────
      # Installs Airflow 2.7 with the Postgres and Amazon providers.
      "pip3 install 'apache-airflow==2.7.0' apache-airflow-providers-postgres apache-airflow-providers-amazon",
      "export AIRFLOW_HOME=/home/ubuntu/airflow && airflow db init",

      # ── JupyterLab ──────────────────────────────────────────────────────────
      "pip3 install jupyterlab",

      # ── PostgreSQL ──────────────────────────────────────────────────────────
      # Used to store KPIs (trending products, abandonment rates) and as
      # Airflow's metadata database.
      "sudo apt-get install -y postgresql postgresql-contrib",
      "sudo systemctl enable postgresql",
      "sudo systemctl start postgresql",
      "sudo -u postgres psql -c \"CREATE USER dataplatform WITH PASSWORD 'dataplatform';\" || true",
      "sudo -u postgres psql -c \"CREATE DATABASE ecommerce OWNER dataplatform;\" || true",

      # ── Nginx ───────────────────────────────────────────────────────────────
      # Reverse proxy: routes port 80 requests to Airflow (:8080).
      "sudo apt-get install -y nginx",
      "sudo systemctl enable nginx",
      "sudo systemctl start nginx",

      # ── Confirmation log ────────────────────────────────────────────────────
      "echo 'Bootstrap complete.' >> /home/ubuntu/bootstrap.log",
      "echo 'Kafka, Spark, Airflow, JupyterLab, PostgreSQL, Nginx installed.' >> /home/ubuntu/bootstrap.log",
      "date >> /home/ubuntu/bootstrap.log"
    ]

    connection {
      type        = "ssh"
      user        = var.ssh_user
      private_key = file(var.private_key_path)
      host        = self.public_ip
    }
  }
}
