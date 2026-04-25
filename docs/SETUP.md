# Setup Guide

Step-by-step instructions for deploying and operating the Data Platform.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [AWS Setup](#aws-setup)
3. [Deploy with Terraform](#deploy-with-terraform)
4. [Post-deploy Configuration](#post-deploy-configuration)
5. [Running the Pipeline](#running-the-pipeline)
6. [Accessing the Web UIs](#accessing-the-web-uis)
7. [Tearing Down](#tearing-down)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

| Tool | Minimum version | Install |
|---|---|---|
| Terraform | 1.5.0 | [hashicorp.com](https://developer.hashicorp.com/terraform/install) |
| AWS CLI | 2.x | [aws.amazon.com](https://aws.amazon.com/cli/) |
| Python | 3.10 | System package or [python.org](https://python.org) |

---

## AWS Setup

### 1. Create an IAM user

In the AWS Console, create an IAM user with the following managed policies:
- `AmazonEC2FullAccess`
- `AmazonS3FullAccess` (needed for the dataset download and Parquet export)

Generate an **Access Key** for programmatic access.

### 2. Create an EC2 key pair

```bash
# Using the AWS CLI:
aws ec2 create-key-pair \
  --key-name data-platform-key \
  --query 'KeyMaterial' \
  --output text > credentials/data-platform.pem

chmod 400 credentials/data-platform.pem
```

Or create the key pair in the AWS Console and download the `.pem` file.

### 3. Write the credentials file

```bash
mkdir -p credentials

cat > credentials/aws_credentials.txt <<EOF
[default]
aws_access_key_id     = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
EOF
```

> **Never commit `credentials/` to version control.** It is listed in `.gitignore`.

---

## Deploy with Terraform

```bash
cd app

# Download providers and initialize the working directory.
terraform init

# Preview all resources that will be created.
terraform plan

# Deploy (takes ~8–12 minutes due to toolchain bootstrap).
terraform apply
```

### Useful apply-time overrides

```bash
# Deploy a larger instance for production
terraform apply -var="env=prod" -var="instance_type=t3.large"

# Use a 200 GB data volume
terraform apply -var="data_volume_size_gb=200"
```

After `apply`, Terraform prints the service URLs:

```
Outputs:

airflow_ui_url          = "http://1.2.3.4:8080"
jupyter_ui_url          = "http://1.2.3.4:8888"
spark_ui_url            = "http://1.2.3.4:4040"
data_platform_public_ip = "1.2.3.4"
data_volume_id          = "vol-0abc123456789def0"
```

---

## Post-deploy Configuration

### Mount the EBS data volume

The EBS volume is attached by Terraform but must be formatted and mounted manually on first use.

```bash
# SSH into the node
ssh -i credentials/data-platform.pem ubuntu@<PUBLIC_IP>

# Run the mount script (requires sudo)
sudo bash /home/ubuntu/scripts/mount_ebs.sh
```

This creates the directory structure under `/data`:

```
/data/
├── raw/          # raw Kafka event batches (JSON)
├── processed/    # Spark ETL output (Parquet)
└── logs/         # Airflow, Spark, and Kafka logs
```

### Initialize Airflow

```bash
# On the node:
export AIRFLOW_HOME=/home/ubuntu/airflow

# Create an admin user for the Airflow UI
airflow users create \
  --username admin \
  --password admin \
  --firstname Admin \
  --lastname User \
  --role Admin \
  --email admin@example.com

# Start the Airflow web server (background)
nohup airflow webserver --port 8080 > /data/logs/airflow/webserver.log 2>&1 &

# Start the Airflow scheduler (background)
nohup airflow scheduler > /data/logs/airflow/scheduler.log 2>&1 &
```

### Configure the Airflow PostgreSQL connection

In the Airflow UI (`http://<IP>:8080`), go to **Admin → Connections** and add:

| Field | Value |
|---|---|
| Connection Id | `postgres_ecommerce` |
| Connection Type | `Postgres` |
| Host | `localhost` |
| Schema | `ecommerce` |
| Login | `dataplatform` |
| Password | `dataplatform` |
| Port | `5432` |

---

## Running the Pipeline

### 1. Start the Kafka producer

```bash
# On the node (streams events in real time):
python3 /home/ubuntu/data/producer.py --rate 20

# Or a limited burst for testing:
python3 /home/ubuntu/data/producer.py --rate 100 --limit 5000
```

### 2. Trigger the Airflow DAG

Open `http://<IP>:8080`, log in, and enable the `ecommerce_pipeline` DAG.  
Trigger it manually with the ▶ button, or let it run on its hourly schedule.

### 3. Monitor

| What | Where |
|---|---|
| DAG runs and task logs | `http://<IP>:8080` |
| Spark job progress | `http://<IP>:4040` (active sessions only) |
| Raw events on disk | `/data/raw/<date>/` |
| Processed Parquet | `/data/processed/<date>/` |

---

## Accessing the Web UIs

| UI | URL | Default credentials |
|---|---|---|
| Apache Airflow | `http://<IP>:8080` | admin / admin |
| JupyterLab | `http://<IP>:8888` | token in `/data/logs/` |
| Apache Spark | `http://<IP>:4040` | — (no auth) |

To start JupyterLab on the node:

```bash
nohup jupyter lab \
  --ip=0.0.0.0 \
  --port=8888 \
  --no-browser \
  --notebook-dir=/home/ubuntu \
  > /data/logs/jupyter.log 2>&1 &

# Get the login token
grep token /data/logs/jupyter.log | head -1
```

---

## Tearing Down

```bash
cd app
terraform destroy
```

> **Note:** The EBS volume is destroyed along with the instance. Back up `/data/processed/` to S3 first if you want to keep the pipeline outputs.

---

## Troubleshooting

### Terraform apply fails at the remote-exec step

- Verify the `.pem` file is at `credentials/data-platform.pem` and has `chmod 400`.
- Check that port 22 is reachable: `nc -vz <IP> 22`.
- Try re-running `terraform apply` — transient network issues during package downloads are common.

### Kafka is not running

```bash
# On the node, check the log:
cat /tmp/kafka.log

# Restart manually:
nohup /opt/kafka/bin/zookeeper-server-start.sh /opt/kafka/config/zookeeper.properties \
  > /data/logs/kafka/zookeeper.log 2>&1 &
sleep 5
nohup /opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties \
  > /data/logs/kafka/kafka.log 2>&1 &
```

### Airflow DAG not visible

```bash
# Copy the DAG to Airflow's DAGs folder:
cp /home/ubuntu/dags/ecommerce_pipeline.py $AIRFLOW_HOME/dags/

# Trigger a DAG reload:
airflow dags list
```

### Out of disk space on the root volume

Pipeline data should always go to `/data/` (the EBS volume), not the root volume.  
Check with `df -h` and move logs to `/data/logs/` if needed.
