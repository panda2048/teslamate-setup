#!/bin/bash
# TeslaMate + Nginx + Swap - Clean & Robust for GCP e2-micro Free Tier
# Safe to run on every boot

set -e

USER_EMAIL=${USER_EMAIL:-""}
if [ -z "$USER_EMAIL" ]; then
    echo "Error: Please set USER_EMAIL=your@email.com"
    exit 1
fi

# Skip if already completed
if [ -f /opt/teslamate/.setup_complete ]; then
    echo "✅ Setup already completed. Skipping."
    echo "Access: https://$(curl -s ifconfig.me)"
    exit 0
fi

echo "🚀 Starting TeslaMate setup for $USER_EMAIL ..."

# 1. Add swap (critical for 1GB RAM)
if [ ! -f /swapfile ]; then
    echo "Adding 2GB swap file..."
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# 2. Install Docker properly
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin nginx apache2-utils

systemctl enable --now docker

# 3. Setup directory
mkdir -p /opt/teslamate && cd /opt/teslamate

# 4. Credentials (only once)
if [ ! -f .credentials ]; then
    ENC=$(openssl rand -hex 32)
    DB=$(openssl rand -hex 16)
    USERNAME="admin"
    PASSWORD=$(openssl rand -hex 12)

    cat > .credentials <<EOF
USERNAME=$USERNAME
PASSWORD=$PASSWORD
EOF
    htpasswd -cb /etc/nginx/.htpasswd $USERNAME $PASSWORD
else
    source .credentials
fi

# 5. Docker Compose
if [ ! -f docker-compose.yml ]; then
    cat > docker-compose.yml <<'EOT'
services:
  teslamate:
    image: teslamate/teslamate:latest
    restart: always
    environment:
      ENCRYPTION_KEY: ${ENC}
      DATABASE_USER: teslamate
      DATABASE_PASS: ${DB}
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
      POSTGRES_PASSWORD: ${DB}
      POSTGRES_DB: teslamate
    volumes:
      - teslamate-db:/var/lib/postgresql/data

  grafana:
    image: teslamate/grafana:latest
    restart: always
    environment:
      DATABASE_USER: teslamate
      DATABASE_PASS: ${DB}
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
fi

docker compose up -d

# 6. Nginx with basic auth
cat > /etc/nginx/sites-available/teslamate <<EOT
server {
    listen 80 default_server;
    server_name _;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl default_server;
    server_name _;

    auth_basic "TeslaMate Secure Access";
    auth_basic_user_file /etc/nginx/.htpasswd;

    location / {
        proxy_pass http://localhost:4000;
        proxy_set_header Host
