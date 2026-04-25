# 🛒 E-Commerce Behavior Pipeline — Data Platform on AWS

> **Infrastructure as Code** · **Real-time streaming** · **Batch processing** · **Orchestration**

A production-grade **Data Engineering** platform fully provisioned with **Terraform**, built around a real e-commerce use case: analyzing user behavior in real time to surface trending products and detect abandoned carts.

---

## 📌 Business Need

An e-commerce company collects millions of user events daily (product views, clicks, ratings, add-to-cart). These events are siloed and processed too slowly to act on:

- The **marketing team** can't identify trending products fast enough to adjust campaigns
- The **retention team** has no real-time signal for cart abandonment
- **Data analysts** spend hours setting up environments instead of analyzing data

**This platform solves all three problems** by providing a fully automated, reproducible data infrastructure that can be spun up with a single `terraform apply`.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       DATA SOURCES                          │
│   Amazon Product Reviews (public S3) — replayed as stream   │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│                    INGESTION LAYER                           │
│                    Apache Kafka                              │
│        Topics: user-events · product-views · ratings        │
└──────────────┬────────────────────────┬─────────────────────┘
               │                        │
               ▼                        ▼
┌──────────────────────┐   ┌────────────────────────────────┐
│   PROCESSING LAYER   │   │      ORCHESTRATION LAYER       │
│    Apache Spark      │   │       Apache Airflow           │
│  ETL · Aggregations  │   │  Schedules & monitors DAGs     │
│  Session windowing   │   │  Alerts on pipeline failures   │
└──────┬───────────────┘   └────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────┐
│                      STORAGE LAYER                          │
│  EBS Volume (raw)  ·  S3 (Parquet)  ·  PostgreSQL (KPIs)   │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                      SERVING LAYER                          │
│        JupyterLab (exploration)  ·  Nginx (dashboard)       │
└─────────────────────────────────────────────────────────────┘

         All infrastructure provisioned by Terraform ↑
```

---

## 📦 What Gets Deployed

| Resource | Details |
|---|---|
| **EC2 instance** | Ubuntu 22.04 LTS — the data platform node |
| **EBS volume** | gp3, configurable size — raw events & logs |
| **Elastic IP** | Static public IP for stable UI access |
| **Security group** | Opens ports for SSH, HTTP/S, Airflow, Jupyter, Spark, Kafka |

### Pre-installed toolchain (via Terraform `remote-exec`)

| Tool | Port | Purpose |
|---|---|---|
| Apache Kafka | `9092` | Real-time event streaming |
| Apache Spark | `4040` | Distributed batch processing |
| Apache Airflow | `8080` | Pipeline orchestration |
| JupyterLab | `8888` | Interactive data exploration |
| PostgreSQL | `5432` | KPI & aggregate storage |
| Nginx | `80 / 443` | Reverse proxy & dashboard |
| Python 3 + pip | — | Scripting & data libraries |
| Java 11 | — | Required by Spark & Kafka |

---

## 📁 Project Structure

```
DataPlatform/
│
├── app/                            # Terraform entry point
│   ├── main.tf                     # Provider, modules, associations
│   ├── variables.tf                # Deployment parameters
│   └── outputs.tf                  # Post-deploy URLs and IPs
│
├── modules/                        # Reusable Terraform modules
│   ├── ec2/                        # Data platform compute node
│   ├── ebs/                        # Persistent data storage volume
│   ├── eip/                        # Static Elastic IP
│   └── sg/                         # Security group (data-tool ports)
│
├── data/
│   └── producer.py                 # Replays Amazon reviews as a Kafka stream
│
├── dags/
│   └── ecommerce_pipeline.py       # Airflow DAG: ingest → transform → load
│
├── notebooks/
│   └── exploration.ipynb           # Trending products & abandonment analysis
│
├── scripts/
│   ├── bootstrap.sh                # Manual re-run of the node setup
│   └── mount_ebs.sh                # Formats and mounts the EBS data volume
│
├── docs/
│   └── SETUP.md                    # Step-by-step deployment guide
│
├── credentials/                    # ⚠️  Gitignored — never commit
├── .gitignore
└── README.md
```

---

## 🚀 Quick Start

### Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.5.0
- An AWS account with programmatic access
- An EC2 key pair (`.pem` file)

### 1 — Configure credentials

```bash
mkdir -p credentials

cat > credentials/aws_credentials.txt <<EOF
[default]
aws_access_key_id     = YOUR_ACCESS_KEY
aws_secret_access_key = YOUR_SECRET_KEY
EOF

cp ~/Downloads/your-key.pem credentials/data-platform.pem
chmod 400 credentials/data-platform.pem
```

### 2 — Deploy

```bash
cd app
terraform init
terraform plan
terraform apply
```

> First deployment takes ~5 minutes — Terraform provisions the infrastructure then bootstraps the full toolchain via SSH.

### 3 — Access your tools

After `apply` completes, Terraform prints the service URLs:

```
airflow_ui_url          = "http://<PUBLIC_IP>:8080"
jupyter_ui_url          = "http://<PUBLIC_IP>:8888"
spark_ui_url            = "http://<PUBLIC_IP>:4040"
data_platform_public_ip = "<PUBLIC_IP>"
```

### 4 — Run the pipeline

```bash
# SSH into the node
ssh -i credentials/data-platform.pem ubuntu@<PUBLIC_IP>

# Mount the EBS data volume (first time only)
sudo bash /home/ubuntu/scripts/mount_ebs.sh

# Start streaming Amazon reviews into Kafka
python3 /home/ubuntu/data/producer.py
```

Open **Airflow at `:8080`** and trigger the `ecommerce_pipeline` DAG.

### 5 — Explore results

Open **JupyterLab at `:8888`** and run `notebooks/exploration.ipynb` to explore:
- Top trending products (last 24 h)
- Sessions with abandoned carts
- Rating distribution by category

### 6 — Tear down

```bash
terraform destroy
```

---

## ⚙️ Configuration

All parameters live in `app/variables.tf`:

| Variable | Default | Description |
|---|---|---|
| `project` | `data-platform` | Prefix for all AWS resource names |
| `env` | `dev` | Environment: `dev` · `staging` · `prod` |
| `aws_region` | `us-east-1` | AWS deployment region |
| `instance_type` | `t3.medium` | EC2 size (min `t3.medium` for Spark) |
| `ssh_key_name` | `data-platform-key` | Name of your AWS key pair |
| `data_volume_size_gb` | `50` | EBS volume size in GB (10–1000) |

Override at apply time:

```bash
terraform apply \
  -var="env=prod" \
  -var="instance_type=t3.large" \
  -var="data_volume_size_gb=200"
```

---

## 🔒 Security Notes

- The security group allows broad ingress (`0.0.0.0/0`) for development. **Restrict CIDR blocks before going to production.**
- The `credentials/` directory is gitignored — never commit keys or `.pem` files.
- For production deployments, replace credential files with **AWS IAM roles** attached to the EC2 instance.

---

## 📚 Dataset

**Amazon Customer Reviews Dataset** — publicly hosted on AWS S3:

```
s3://amazon-reviews-pds/tsv/
```

`data/producer.py` downloads the `Electronics` category subset and replays it row-by-row into Kafka, simulating a live user-event stream at a configurable rate (default: 10 events/sec).

---

## 📄 License

MIT — see [LICENSE](LICENSE) for details.
