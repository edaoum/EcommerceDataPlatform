#!/usr/bin/env bash
# =============================================================================
# scripts/mount_ebs.sh
# Formats and mounts the EBS data volume on first use.
#
# Run this script once after the first `terraform apply`, via SSH:
#   sudo bash /home/ubuntu/scripts/mount_ebs.sh
#
# What it does:
#   1. Detects the EBS device path (varies by instance type and kernel)
#   2. Formats the volume with ext4 (only if not already formatted)
#   3. Creates the /data mount point
#   4. Mounts the volume and adds it to /etc/fstab for persistence across reboots
#   5. Creates the expected directory structure under /data
#
# After running, the following directories will be available:
#   /data/raw/          → raw Kafka event batches (JSON)
#   /data/processed/    → Spark ETL output (Parquet)
#   /data/logs/         → pipeline and tool logs
# =============================================================================

set -euo pipefail

# ── Device detection ──────────────────────────────────────────────────────────
# AWS may expose the volume as /dev/xvdf (older instances) or /dev/nvme1n1
# (Nitro-based instances like t3, m5, r5). We detect which one exists.
if [ -b /dev/nvme1n1 ]; then
    DEVICE="/dev/nvme1n1"
elif [ -b /dev/xvdf ]; then
    DEVICE="/dev/xvdf"
else
    echo "ERROR: Could not find the EBS data volume."
    echo "Make sure the volume is attached (check terraform apply output)."
    exit 1
fi

MOUNT_POINT="/data"

echo "=== Data Platform — EBS Volume Setup ==="
echo "Device    : $DEVICE"
echo "Mount at  : $MOUNT_POINT"
echo ""

# ── Format only if not already formatted ─────────────────────────────────────
# blkid returns an empty string if the device has no filesystem.
if ! blkid "$DEVICE" &>/dev/null; then
    echo "[1/4] Formatting $DEVICE with ext4..."
    mkfs.ext4 -L data-platform "$DEVICE"
    echo "      Done."
else
    echo "[1/4] $DEVICE is already formatted — skipping mkfs."
fi

# ── Create mount point ────────────────────────────────────────────────────────
echo "[2/4] Creating mount point at $MOUNT_POINT..."
mkdir -p "$MOUNT_POINT"

# ── Mount the volume ──────────────────────────────────────────────────────────
echo "[3/4] Mounting $DEVICE at $MOUNT_POINT..."
mount "$DEVICE" "$MOUNT_POINT"

# Add to /etc/fstab so the volume re-mounts automatically after reboot.
# We use the LABEL set during mkfs to be device-path-independent.
FSTAB_ENTRY="LABEL=data-platform  $MOUNT_POINT  ext4  defaults,nofail  0  2"
if ! grep -q "data-platform" /etc/fstab; then
    echo "$FSTAB_ENTRY" >> /etc/fstab
    echo "      Added to /etc/fstab."
fi

# ── Create directory structure ────────────────────────────────────────────────
echo "[4/4] Creating directory structure under $MOUNT_POINT..."
mkdir -p \
    "$MOUNT_POINT/raw" \
    "$MOUNT_POINT/processed" \
    "$MOUNT_POINT/logs/airflow" \
    "$MOUNT_POINT/logs/spark" \
    "$MOUNT_POINT/logs/kafka"

# Give the ubuntu user ownership so scripts run without sudo.
chown -R ubuntu:ubuntu "$MOUNT_POINT"

echo ""
echo "=== Setup complete ==="
df -h "$MOUNT_POINT"
echo ""
echo "Directory structure:"
ls -la "$MOUNT_POINT"
