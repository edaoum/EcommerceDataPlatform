"""
data/producer.py
================
Kafka producer that replays the Amazon Customer Reviews dataset as a
simulated real-time user-event stream.

Dataset: Amazon Customer Reviews — Electronics category (public S3)
  s3://amazon-reviews-pds/tsv/amazon_reviews_us_Electronics_v1_00.tsv.gz

Each row in the dataset becomes a JSON event published to one of three
Kafka topics, mimicking actual e-commerce traffic:
  - user-events   : all events (view, rating, add-to-cart)
  - product-views : product page views only
  - ratings       : rating submissions only

Usage:
    python3 producer.py [--rate EVENTS_PER_SECOND] [--limit MAX_EVENTS]

Examples:
    python3 producer.py                # default: 10 events/sec, no limit
    python3 producer.py --rate 50      # fast replay for testing
    python3 producer.py --limit 10000  # stop after 10 000 events
"""

import argparse
import gzip
import json
import logging
import os
import sys
import time
import urllib.request
from datetime import datetime, timezone

from kafka import KafkaProducer
from kafka.errors import NoBrokersAvailable

# ── Logging setup ────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)

# ── Constants ─────────────────────────────────────────────────────────────────
KAFKA_BROKER = os.getenv("KAFKA_BROKER", "localhost:9092")
DATASET_URL = (
    "https://s3.amazonaws.com/amazon-reviews-pds/tsv/"
    "amazon_reviews_us_Electronics_v1_00.tsv.gz"
)
LOCAL_DATASET = "/data/amazon_reviews_electronics.tsv.gz"

# Kafka topic routing
TOPIC_ALL    = "user-events"
TOPIC_VIEWS  = "product-views"
TOPIC_RATINGS = "ratings"

# TSV column names (from the Amazon dataset README)
COLUMNS = [
    "marketplace", "customer_id", "review_id", "product_id",
    "product_parent", "product_title", "product_category",
    "star_rating", "helpful_votes", "total_votes", "vine",
    "verified_purchase", "review_headline", "review_body", "review_date",
]


def download_dataset() -> None:
    """Download the Amazon reviews dataset if not already cached locally."""
    if os.path.exists(LOCAL_DATASET):
        log.info("Dataset already cached at %s — skipping download.", LOCAL_DATASET)
        return

    os.makedirs(os.path.dirname(LOCAL_DATASET), exist_ok=True)
    log.info("Downloading dataset from S3 (~500 MB). This may take a few minutes...")
    urllib.request.urlretrieve(DATASET_URL, LOCAL_DATASET)
    log.info("Download complete: %s", LOCAL_DATASET)


def build_producer() -> KafkaProducer:
    """Create and return a Kafka producer with JSON serialization."""
    try:
        producer = KafkaProducer(
            bootstrap_servers=KAFKA_BROKER,
            value_serializer=lambda v: json.dumps(v).encode("utf-8"),
            # Batch small messages for efficiency.
            batch_size=16384,
            linger_ms=10,
            # Retry on transient broker errors.
            retries=3,
        )
        log.info("Connected to Kafka broker at %s.", KAFKA_BROKER)
        return producer
    except NoBrokersAvailable:
        log.error(
            "Cannot reach Kafka broker at %s. "
            "Make sure Kafka is running (check /tmp/kafka.log).",
            KAFKA_BROKER,
        )
        sys.exit(1)


def row_to_event(row: dict) -> dict:
    """
    Transform a raw dataset row into a structured event payload.

    Adds:
      - event_type : derived from star_rating (view / rating / add-to-cart)
      - ingested_at: current UTC timestamp (simulates real-time ingestion)
      - session_id : synthetic session derived from customer_id + date
    """
    star = int(row.get("star_rating", 3) or 3)

    # Simulate different event types based on rating score.
    if star >= 4:
        event_type = "rating"        # Satisfied user submitted a review
    elif star <= 2:
        event_type = "add-to-cart"   # Considered buying but likely abandoned
    else:
        event_type = "product-view"  # Neutral browse

    return {
        "event_type":       event_type,
        "customer_id":      row.get("customer_id"),
        "product_id":       row.get("product_id"),
        "product_title":    row.get("product_title"),
        "product_category": row.get("product_category"),
        "star_rating":      star,
        "helpful_votes":    int(row.get("helpful_votes", 0) or 0),
        "verified_purchase": row.get("verified_purchase") == "Y",
        "review_date":      row.get("review_date"),
        "ingested_at":      datetime.now(timezone.utc).isoformat(),
        # Synthetic session ID — groups events by customer + day.
        "session_id": f"{row.get('customer_id')}_{row.get('review_date', 'unknown')}",
    }


def stream_events(producer: KafkaProducer, rate: float, limit: int) -> None:
    """
    Read the dataset row by row and publish each row as a Kafka event.

    Args:
        producer : KafkaProducer instance.
        rate     : Target events per second (throttled with time.sleep).
        limit    : Maximum number of events to publish (0 = no limit).
    """
    interval = 1.0 / rate  # seconds between events
    count = 0

    log.info("Starting stream at %.1f events/sec (limit: %s).", rate, limit or "none")

    with gzip.open(LOCAL_DATASET, "rt", encoding="utf-8", errors="replace") as fh:
        header = fh.readline().strip().split("\t")  # First line is the header

        for line in fh:
            if limit and count >= limit:
                log.info("Reached event limit (%d). Stopping.", limit)
                break

            # Parse the TSV row into a dict.
            values = line.strip().split("\t")
            row = dict(zip(header if header else COLUMNS, values))

            event = row_to_event(row)

            # ── Publish to topic: user-events (all events) ───────────────────
            producer.send(TOPIC_ALL, value=event)

            # ── Publish to specific sub-topic based on event type ────────────
            if event["event_type"] == "product-view":
                producer.send(TOPIC_VIEWS, value=event)
            elif event["event_type"] == "rating":
                producer.send(TOPIC_RATINGS, value=event)

            count += 1

            # Progress log every 1000 events.
            if count % 1000 == 0:
                log.info("Published %d events so far.", count)

            time.sleep(interval)

    producer.flush()
    log.info("Stream finished. Total events published: %d.", count)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Replay Amazon product reviews as a Kafka event stream."
    )
    parser.add_argument(
        "--rate",
        type=float,
        default=10.0,
        help="Number of events to publish per second (default: 10).",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Maximum events to publish before stopping (default: 0 = no limit).",
    )
    args = parser.parse_args()

    download_dataset()
    producer = build_producer()

    try:
        stream_events(producer, rate=args.rate, limit=args.limit)
    except KeyboardInterrupt:
        log.info("Interrupted by user. Flushing pending messages...")
        producer.flush()
    finally:
        producer.close()
        log.info("Producer closed.")


if __name__ == "__main__":
    main()
