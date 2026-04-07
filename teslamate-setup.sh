#!/bin/bash
# TeslaMate + Nginx + Basic Auth - Fixed for GCP e2-micro
# Fully automatic, robust on low RAM, fixes docker compose issue

set -e

USER_EMAIL=${USER_EMAIL:-""}
if [ -z "$USER_EMAIL" ]; then
    echo "Error: Use USER_EMAIL=your@email.com in the startup script"
    exit 1
fi

echo "🚀 Starting TeslaMate setup for $USER_EMAIL ..."

# === Fix installation issues first ===
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release

# Add official Docker repository (this fixes docker compose)
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | \
tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update

# Install clean Docker + Compose plugin + other packages
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin nginx apache2-utils

systemctl enable --now docker

# Cleanup heavy broken Google package if present
apt-get remove --purge -y google-cloud-cli google-cloud-cli-anthoscli || true

mkdir -p /opt/teslamate && cd /opt/teslamate

# Generate credentials only once
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

# TeslaMate docker-compose
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

# Start services with proper docker compose
docker compose up -d

# Nginx config with basic auth + HTTP→HTTPS redirect
cat > /etc/nginx/sites-available/teslamate <<EOT
server {
    listen 80 default_server;
    server_name _;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl default_server;
    server_name _;

    ssl_certificate /etc/letsencrypt/live/default/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/default/privkey.pem;

    auth_basic "TeslaMate Secure Access";
    auth_basic_user_file /etc/nginx/.htpasswd;

    location / {
        proxy_pass http://localhost:4000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOT

ln -sf /etc/nginx/sites-available/teslamate /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx

PUBLIC_IP=$(curl -s ifconfig.me)

echo "========================================"
echo "✅ SETUP COMPLETE!"
echo "========================================"
echo "URL      : https://$PUBLIC_IP"
echo "Username : admin"
echo "Password : $PASSWORD"
echo ""
echo "Details saved in /opt/teslamate/.credentials"
cat > /opt/teslamate/.credentials <<EOC
URL: https://$PUBLIC_IP
Username: admin
Password: $PASSWORD
EOC
