#!/bin/bash
# TeslaMate with Cloudflare Tunnel - Clean & Idempotent Version
# Usage: curl ... | TUNNEL_TOKEN=xxx bash

set -e

TUNNEL_TOKEN=${TUNNEL_TOKEN:-""}
if [ -z "$TUNNEL_TOKEN" ]; then
    echo "Error: Please provide tunnel token"
    echo "Usage: ... | TUNNEL_TOKEN=your-token-here bash"
    exit 1
fi

# Skip if already completed (important for reboots)
if [ -f /opt/teslamate/.setup_complete ]; then
    echo "✅ TeslaMate setup already completed. Skipping."
    echo "Tunnel is running. Access via your Cloudflare public hostname."
    exit 0
fi

echo "🚀 Starting TeslaMate with Cloudflare Tunnel ..."

# Add swap for stability
if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# Install Docker
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin curl

systemctl enable --now docker

mkdir -p /opt/teslamate && cd /opt/teslamate

# Generate credentials only once
if [ ! -f .credentials ]; then
    ENC=$(openssl rand -hex 32)
    DB=$(openssl rand -hex 16)

    cat > .credentials <<EOF
ENC=$ENC
DB=$DB
EOF
fi

source .credentials

# Docker Compose
cat > docker-compose.yml <<EOT
services:
  teslamate:
    image: teslamate/teslamate:latest
    restart: always
    environment:
      ENCRYPTION_KEY: $ENC
      DATABASE_USER: teslamate
      DATABASE_PASS: $DB
      DATABASE_NAME: teslamate
      DATABASE_HOST: database
      MQTT_HOST: mosquitto
    volumes:
      - ./import:/opt/app/import

  database:
    image: postgres:16
    restart: always
    environment:
      POSTGRES_USER: teslamate
      POSTGRES_PASSWORD: $DB
      POSTGRES_DB: teslamate
    volumes:
      - teslamate-db:/var/lib/postgresql/data

  grafana:
    image: teslamate/grafana:latest
    restart: always
    environment:
      DATABASE_USER: teslamate
      DATABASE_PASS: $DB
      DATABASE_NAME: teslamate
      DATABASE_HOST: database
    volumes:
      - teslamate-grafana:/var/lib/grafana

  mosquitto:
    image: eclipse-mosquitto:2
    restart: always
    command: mosquitto -c /mosquitto/no-auth.conf

volumes:
  teslamate-db:
  teslamate-grafana:
EOT

docker compose up -d

# Install and start Cloudflare Tunnel
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o cloudflared.deb
dpkg -i cloudflared.deb
cloudflared service install $TUNNEL_TOKEN
systemctl enable --now cloudflared

# Mark as completed
touch /opt/teslamate/.setup_complete

echo "========================================"
echo "✅ SETUP COMPLETE!"
echo "========================================"
echo "TeslaMate is running."
echo "Go back to Cloudflare dashboard and add Public Hostname:"
echo "   Service → http://localhost:4000"
echo ""
echo "Setup will not run again on reboot."
