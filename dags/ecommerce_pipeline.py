"""
dags/ecommerce_pipeline.py
==========================
Airflow DAG — E-Commerce Behavior Pipeline.

This DAG orchestrates the full data engineering pipeline:

  [ingest_from_kafka]
        |
  [transform_with_spark]
        |
   ┌────┴──────┐
   |           |
[load_kpis] [export_parquet]
   |
[check_data_quality]

Schedule: every hour (can be adjusted via the `schedule_interval` parameter).

Business outputs:
  - Trending products (top 20 by rating count in the last 24 h)
  - Abandoned cart sessions (add-to-cart events with no subsequent purchase)
  - Rating distribution by category

KPIs are written to PostgreSQL (table: ecommerce.kpis) and can be queried
from JupyterLab or the Nginx dashboard.
"""

from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from airflow.providers.postgres.hooks.postgres import PostgresHook

# ── Default arguments applied to every task ──────────────────────────────────
DEFAULT_ARGS = {
    "owner": "data-team",
    "depends_on_past": False,
    "email_on_failure": False,      # Set to True and add email in production
    "email_on_retry": False,
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
}

# ── DAG definition ────────────────────────────────────────────────────────────
with DAG(
    dag_id="ecommerce_pipeline",
    description="Ingest Kafka events → Spark ETL → PostgreSQL KPIs",
    default_args=DEFAULT_ARGS,
    start_date=datetime(2024, 1, 1),
    schedule_interval="@hourly",
    catchup=False,                  # Don't backfill missed runs
    tags=["ecommerce", "kafka", "spark", "postgres"],
) as dag:

    # ── Task 1: Ingest ────────────────────────────────────────────────────────
    # Reads a batch of messages from the Kafka 'user-events' topic and saves
    # them as raw JSON files on the EBS data volume (/data/raw/).
    ingest_from_kafka = BashOperator(
        task_id="ingest_from_kafka",
        bash_command="""
            python3 /home/ubuntu/data/kafka_batch_consumer.py \
                --topic user-events \
                --output /data/raw/{{ ds }}/{{ ts_nodash }} \
                --max-messages 50000
        """,
        doc_md="""
        **Ingest from Kafka**
        Consumes up to 50 000 messages from the `user-events` topic and
        writes them as gzipped JSON to `/data/raw/<date>/<timestamp>/`.
        """,
    )

    # ── Task 2: Transform ─────────────────────────────────────────────────────
    # Runs a PySpark job that reads raw JSON events, applies session windowing,
    # computes trending products and abandonment rates, and writes Parquet.
    transform_with_spark = BashOperator(
        task_id="transform_with_spark",
        bash_command="""
            /opt/spark/bin/spark-submit \
                --master local[*] \
                --driver-memory 2g \
                /home/ubuntu/scripts/spark_transform.py \
                    --input  /data/raw/{{ ds }} \
                    --output /data/processed/{{ ds }}
        """,
        doc_md="""
        **Transform with Spark**
        PySpark job (local[*] mode) that:
        - Parses and validates raw JSON events
        - Applies 1-hour session windows
        - Computes: trending products, abandoned carts, rating distribution
        - Outputs Parquet files to `/data/processed/<date>/`
        """,
    )

    # ── Task 3a: Load KPIs into PostgreSQL ────────────────────────────────────
    def load_kpis_to_postgres(ds: str, **kwargs) -> None:
        """
        Read the Spark-processed Parquet output and upsert KPIs into PostgreSQL.

        Tables written:
          - ecommerce.trending_products  : top products by hourly rating count
          - ecommerce.abandoned_sessions : sessions with add-to-cart but no purchase
          - ecommerce.rating_distribution: star rating breakdown per category
        """
        import pandas as pd

        pg = PostgresHook(postgres_conn_id="postgres_ecommerce")

        # ── Trending products ─────────────────────────────────────────────────
        trending_path = f"/data/processed/{ds}/trending_products"
        if os.path.exists(trending_path):
            df_trending = pd.read_parquet(trending_path)
            df_trending["computed_at"] = datetime.utcnow()

            pg.insert_rows(
                table="ecommerce.trending_products",
                rows=df_trending[
                    ["product_id", "product_title", "category",
                     "rating_count", "avg_rating", "computed_at"]
                ].values.tolist(),
                target_fields=[
                    "product_id", "product_title", "category",
                    "rating_count", "avg_rating", "computed_at",
                ],
                replace=True,
            )

        # ── Abandoned sessions ────────────────────────────────────────────────
        abandoned_path = f"/data/processed/{ds}/abandoned_sessions"
        if os.path.exists(abandoned_path):
            df_abandoned = pd.read_parquet(abandoned_path)
            df_abandoned["computed_at"] = datetime.utcnow()

            pg.insert_rows(
                table="ecommerce.abandoned_sessions",
                rows=df_abandoned[
                    ["session_id", "customer_id", "product_id",
                     "last_event", "computed_at"]
                ].values.tolist(),
                target_fields=[
                    "session_id", "customer_id", "product_id",
                    "last_event", "computed_at",
                ],
                replace=True,
            )

        print(f"KPIs loaded to PostgreSQL for {ds}.")

    # Import os inside the function scope so Airflow can serialize the task.
    import os

    load_kpis = PythonOperator(
        task_id="load_kpis",
        python_callable=load_kpis_to_postgres,
        doc_md="""
        **Load KPIs to PostgreSQL**
        Reads Parquet files produced by Spark and upserts KPIs into:
        - `ecommerce.trending_products`
        - `ecommerce.abandoned_sessions`
        - `ecommerce.rating_distribution`
        """,
    )

    # ── Task 3b: Export Parquet to S3 ─────────────────────────────────────────
    # Archives processed data to S3 for long-term storage and potential
    # consumption by other teams (e.g. ML training, BI tools).
    export_parquet = BashOperator(
        task_id="export_parquet",
        bash_command="""
            aws s3 sync \
                /data/processed/{{ ds }} \
                s3://$DATA_BUCKET/processed/{{ ds }}/ \
                --storage-class STANDARD_IA
        """,
        env={"DATA_BUCKET": "your-data-platform-bucket"},   # Update with your bucket name
        doc_md="""
        **Export Parquet to S3**
        Syncs the processed Parquet files to S3 (STANDARD_IA storage class)
        for long-term archival and cross-team access.
        """,
    )

    # ── Task 4: Data quality check ────────────────────────────────────────────
    def check_data_quality(ds: str, **kwargs) -> None:
        """
        Run basic data quality assertions on the loaded KPIs.

        Raises:
            ValueError: if any quality check fails, causing the task to fail
                        and Airflow to retry or alert.
        """
        pg = PostgresHook(postgres_conn_id="postgres_ecommerce")

        # Check 1: At least one trending product was loaded for today.
        row_count = pg.get_first(
            "SELECT COUNT(*) FROM ecommerce.trending_products WHERE computed_at::date = %s",
            parameters=(ds,),
        )[0]
        if row_count == 0:
            raise ValueError(
                f"Data quality FAILED: no trending products found for {ds}. "
                "Check the Spark job and Kafka consumer outputs."
            )

        # Check 2: No NULL product IDs in the trending table.
        null_count = pg.get_first(
            "SELECT COUNT(*) FROM ecommerce.trending_products WHERE product_id IS NULL",
        )[0]
        if null_count > 0:
            raise ValueError(
                f"Data quality FAILED: {null_count} rows with NULL product_id in trending_products."
            )

        print(f"Data quality checks passed for {ds}. {row_count} trending products loaded.")

    check_quality = PythonOperator(
        task_id="check_data_quality",
        python_callable=check_data_quality,
        doc_md="""
        **Data quality check**
        Asserts that:
        - At least one trending product was loaded for the run date
        - No NULL product IDs exist in the trending table
        Fails the DAG run if any check is violated.
        """,
    )

    # ── Task dependencies ─────────────────────────────────────────────────────
    # ingest → transform → [load_kpis, export_parquet] → quality_check
    ingest_from_kafka >> transform_with_spark >> [load_kpis, export_parquet]
    load_kpis >> check_quality
