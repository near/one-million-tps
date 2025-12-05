#!/bin/bash
# Logs: /var/log/prometheus-startup.log

set -euo pipefail
LOG_FILE="/var/log/prometheus-startup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

PROM_VERSION="3.5.0"
PROM_NAME="prometheus-${PROM_VERSION}.linux-amd64"
PROM_TARBALL="${PROM_NAME}.tar.gz"
PROM_URL="https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/${PROM_TARBALL}"
MOCKNET_ID=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/mocknet_id)
PROJECT=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)
echo "[INFO] MOCKNET_ID=${MOCKNET_ID}"

echo "[INFO] Starting Prometheus setup (v${PROM_VERSION})..."

# --- System prep -------------------------------------------------------------
echo "[INFO] Updating apt package index..."
export DEBIAN_FRONTEND=noninteractive
retry_apt() {
  for i in {1..5}; do
    if apt-get update && apt-get install -y wget ca-certificates tar; then
      return 0
    fi
    echo "[WARN] apt failed (attempt $i), retrying in 5s..."
    sleep 5
  done
  echo "[ERROR] apt install failed after retries"
  return 1
}
retry_apt

# --- Create user/group and directories ---------------------------------------
echo "[INFO] Creating prometheus user/group if needed..."
if ! getent group prometheus >/dev/null; then
  groupadd --system prometheus
fi

# Prefer /usr/sbin/nologin if present, fallback to /sbin/nologin
NOLOGIN="/usr/sbin/nologin"
[ -x /sbin/nologin ] && NOLOGIN="/sbin/nologin"

if ! id -u prometheus >/dev/null 2>&1; then
  useradd --system --no-create-home \
    --shell "$NOLOGIN" \
    --gid prometheus \
    prometheus
fi

echo "[INFO] Creating directories..."
mkdir -p /etc/prometheus
mkdir -p /var/lib/prometheus
chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

# --- Download & install binaries ---------------------------------------------
if ! command -v prometheus >/dev/null 2>&1 || ! prometheus --version 2>/dev/null | grep -q "version ${PROM_VERSION}"; then
  echo "[INFO] Downloading Prometheus ${PROM_VERSION}..."
  cd /tmp
  rm -f "${PROM_TARBALL}"
  wget -q "${PROM_URL}"
  echo "[INFO] Extracting ${PROM_TARBALL}..."
  rm -rf "/tmp/${PROM_NAME}"
  tar xf "${PROM_TARBALL}"

  echo "[INFO] Installing binaries..."
  install -o root -g root -m 0755 "/tmp/${PROM_NAME}/prometheus" /usr/local/bin/prometheus
  install -o root -g root -m 0755 "/tmp/${PROM_NAME}/promtool"   /usr/local/bin/promtool
  chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool

  echo "[INFO] Installing default config (non-destructive)..."
  # Only copy default files if they don't already exist
  if [ ! -f /etc/prometheus/prometheus.yml ]; then
    cp "/tmp/${PROM_NAME}/prometheus.yml" /etc/prometheus/prometheus.yml
  fi

  chown -R prometheus:prometheus /etc/prometheus
  chown -R prometheus:prometheus /var/lib/prometheus
else
  echo "[INFO] Prometheus ${PROM_VERSION} already present, skipping download."
fi

# Generate GCE zones YAML and store in variable
ZONES_YAML=$(gcloud compute zones list --format="value(name)" | while read -r zone; do
  echo "    - project: ${PROJECT}"
  echo "      zone: ${zone}"
  echo
done)


# --- Minimal sane default config (scrape itself) -----------------------------
if ! grep -q "job_name: 'prometheus'" /etc/prometheus/prometheus.yml 2>/dev/null; then
  echo "[INFO] Writing minimal /etc/prometheus/prometheus.yml..."
cat >/etc/prometheus/prometheus.yml << YAML
global:
  evaluation_interval: 1m
  scrape_interval: 1m
  scrape_timeout: 15s
  external_labels:
    environment: prometheus-scrapper.nearone.internal
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  - job_name: gce_neard_metrics
    relabel_configs:
    - action: keep
      source_labels: [__meta_gce_instance_name]
      regex: '^(mocknet-${MOCKNET_ID}.*)$'
    - action: keep
      regex: neard.*
      source_labels:
      - __meta_gce_label_binary
    - source_labels:
      - __meta_gce_label_binary
      target_label: binary
    - regex: (.+)
      replacement: \${1}:3030
      source_labels:
      - __meta_gce_public_ip
      target_label: __address__
    - source_labels:
      - __meta_gce_instance_id
      target_label: instance_id
    - source_labels:
      - __meta_gce_instance_name
      target_label: node_id
    - source_labels:
      - __meta_gce_label_chain_id
      target_label: chain_id
    - source_labels:
      - __meta_gce_label_node_type
      target_label: node_type
    - source_labels:
      - __meta_gce_label_role
      target_label: role
    - source_labels:
      - __meta_gce_label_canary
      target_label: canary
    gce_sd_configs:
${ZONES_YAML}
YAML
  chown prometheus:prometheus /etc/prometheus/prometheus.yml
fi

# --- systemd unit ------------------------------------------------------------
echo "[INFO] Creating systemd service..."
cat >/etc/systemd/system/prometheus.service <<'UNIT'
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target
[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --web.listen-address=:9090
Restart=on-failure
RestartSec=5s
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
UNIT
echo "[INFO] Reloading systemd and enabling service..."
systemctl daemon-reload
systemctl enable --now prometheus
# --- Optional UFW rule (on GCE you usually open VPC firewall instead) -------
if command -v ufw >/dev/null 2>&1; then
  echo "[INFO] Ensuring UFW allows 9090/tcp (if UFW is active)..."
  if ufw status | grep -qi "Status: active"; then
    ufw allow 9090/tcp || true
  else
    echo "[INFO] UFW installed but not active; skipping rule."
  fi
else
  echo "[INFO] UFW not installed; if you need host firewall rules, install UFW or use GCP VPC firewall."
fi
# --- Final status ------------------------------------------------------------
echo "[INFO] Prometheus service status:"
systemctl --no-pager --full status prometheus || true
echo "[INFO] Completed Prometheus setup."