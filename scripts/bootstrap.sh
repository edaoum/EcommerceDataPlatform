#!/usr/bin/env bash
# =============================================================================
# scripts/bootstrap.sh
# Manual re-run of the data platform toolchain setup.
#
# Terraform runs this automatically via remote-exec on first apply.
# Use this script to re-run setup after an instance rebuild, or to install
# a tool that was missing from the original bootstrap.
#
# Run on the EC2 node:
#   bash /home/ubuntu/scripts/bootstrap.sh
# =============================================================================

set -euo pipefail

LOG_FILE="/home/ubuntu/bootstrap.log"
echo "=== Data Platform Bootstrap — $(date) ===" | tee -a "$LOG_FILE"

# ── System update ─────────────────────────────────────────────────────────────
echo "[1/7] Updating system packages..." | tee -a "$LOG_FILE"
sudo apt-get update -y
sudo apt-get upgrade -y

# ── Core dependencies ─────────────────────────────────────────────────────────
echo "[2/7] Installing core dependencies (Java 11, Python 3, tools)..." | tee -a "$LOG_FILE"
sudo apt-get install -y \
    python3 python3-pip python3-venv \
    openjdk-11-jdk \
    curl wget git unzip \
    postgresql postgresql-contrib \
    nginx

# ── Apache Kafka 3.6 ─────────────────────────────────────────────────────────
echo "[3/7] Installing Apache Kafka 3.6..." | tee -a "$LOG_FILE"
if [ ! -d /opt/kafka ]; then
    wget -q https://downloads.apache.org/kafka/3.6.0/kafka_2.13-3.6.0.tgz -O /tmp/kafka.tgz
    sudo tar -xzf /tmp/kafka.tgz -C /opt
    sudo ln -sf /opt/kafka_2.13-3.6.0 /opt/kafka
fi

# Start ZooKeeper and Kafka (in background).
nohup /opt/kafka/bin/zookeeper-server-start.sh /opt/kafka/config/zookeeper.properties \
    > /data/logs/kafka/zookeeper.log 2>&1 &
sleep 5
nohup /opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties \
    > /data/logs/kafka/kafka.log 2>&1 &
sleep 5

# Create topics.
/opt/kafka/bin/kafka-topics.sh --create --topic user-events    \
    --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1 || true
/opt/kafka/bin/kafka-topics.sh --create --topic product-views  \
    --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1 || true
/opt/kafka/bin/kafka-topics.sh --create --topic ratings        \
    --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1 || true

echo "    Kafka topics created." | tee -a "$LOG_FILE"

# ── Apache Spark 3.5 ─────────────────────────────────────────────────────────
echo "[4/7] Installing Apache Spark 3.5..." | tee -a "$LOG_FILE"
if [ ! -d /opt/spark ]; then
    wget -q https://downloads.apache.org/spark/spark-3.5.0/spark-3.5.0-bin-hadoop3.tgz \
        -O /tmp/spark.tgz
    sudo tar -xzf /tmp/spark.tgz -C /opt
    sudo ln -sf /opt/spark-3.5.0-bin-hadoop3 /opt/spark
fi

grep -q "SPARK_HOME" ~/.bashrc || echo 'export SPARK_HOME=/opt/spark' >> ~/.bashrc
grep -q "spark/bin" ~/.bashrc  || echo 'export PATH=$PATH:$SPARK_HOME/bin' >> ~/.bashrc

# ── Python libraries ──────────────────────────────────────────────────────────
echo "[5/7] Installing Python data libraries..." | tee -a "$LOG_FILE"
pip3 install --upgrade pip
pip3 install \
    pandas pyarrow boto3 \
    sqlalchemy psycopg2-binary \
    kafka-python \
    pyspark==3.5.0 \
    "apache-airflow==2.7.0" \
    apache-airflow-providers-postgres \
    apache-airflow-providers-amazon \
    jupyterlab

# ── Apache Airflow ────────────────────────────────────────────────────────────
echo "[6/7] Initializing Apache Airflow..." | tee -a "$LOG_FILE"
export AIRFLOW_HOME=/home/ubuntu/airflow
airflow db init
echo "    Airflow DB initialized." | tee -a "$LOG_FILE"

# ── PostgreSQL ────────────────────────────────────────────────────────────────
echo "[7/7] Configuring PostgreSQL..." | tee -a "$LOG_FILE"
sudo systemctl enable postgresql
sudo systemctl start postgresql
sudo -u postgres psql -c "CREATE USER dataplatform WITH PASSWORD 'dataplatform';" || true
sudo -u postgres psql -c "CREATE DATABASE ecommerce OWNER dataplatform;" || true

# Nginx
sudo systemctl enable nginx
sudo systemctl start nginx

echo "" | tee -a "$LOG_FILE"
echo "=== Bootstrap complete — $(date) ===" | tee -a "$LOG_FILE"
echo "Check $LOG_FILE for the full log." | tee -a "$LOG_FILE"
