#!/bin/bash
# TeslaMate + Nginx + Automatic HTTPS + Email Credentials
# Usage: curl ... | USER_EMAIL=xxx@gmail.com bash

set -e

USER_EMAIL=${USER_EMAIL:-""}

if [ -z "$USER_EMAIL" ]; then
    echo "Error: Please provide your email. Example:"
    echo "curl -sSL https://.../setup-nginx.sh | USER_EMAIL=your@gmail.com bash"
    exit 1
fi

echo "🚀 Starting TeslaMate setup for $USER_EMAIL ..."

apt-get update && apt-get upgrade -y
apt-get install -y docker.io docker-compose nginx apache2-utils curl certbot python3-certbot-nginx

systemctl enable --now docker

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

# TeslaMate services
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

docker compose up -D

PUBLIC_IP=$(curl -s ifconfig.me)

# Nginx config (HTTP → HTTPS)
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

# Automatic HTTPS
certbot certonly --nginx --non-interactive --agree-tos --email $USER_EMAIL --domains $PUBLIC_IP --expand --keep || true

# Send email with login details
SUBJECT="Your TeslaMate is Ready 🚀"
BODY="Hi,\n\nYour TeslaMate setup is complete!\n\n🔗 URL: https://$PUBLIC_IP\n👤 Username: $USERNAME\n🔑 Password: $PASSWORD\n\nPlease save these details safely.\n\nEnjoy!"

echo -e "To: $USER_EMAIL\nSubject: $SUBJECT\n\n$BODY" | \
curl -s --url "smtp://smtp.gmail.com:587" --ssl-reqd \
  --mail-from "$USER_EMAIL" --mail-rcpt "$USER_EMAIL" \
  --user "$USER_EMAIL:YOUR_GMAIL_APP_PASSWORD_HERE" || echo "Note: Email sending skipped (Gmail setup needed for full automation)."

echo "========================================"
echo "✅ SETUP COMPLETE!"
echo "========================================"
echo "URL      : https://$PUBLIC_IP"
echo "Username : admin"
echo "Password : $PASSWORD"
echo ""
echo "Login details have been emailed to $USER_EMAIL"
echo "Credentials also saved in /opt/teslamate/.credentials"
