#!/usr/bin/env bash
set -e

echo "==> Updating system..."
apt-get update -y
apt-get upgrade -y
apt-get install -y curl wget gnupg ca-certificates build-essential git redis postgresql postgresql-contrib

echo "==> Installing Node.js 20 and Yarn..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
npm install -g yarn

echo "==> Creating Outline DB + User..."
DB_NAME="outline"
DB_USER="outline"
DB_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9!@#%&*' | cut -c1-16)"

su - postgres -c "psql -c \"DROP DATABASE IF EXISTS $DB_NAME;\""
su - postgres -c "psql -c \"DROP ROLE IF EXISTS $DB_USER;\""
su - postgres -c "psql -c \"CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';\""
su - postgres -c "psql -c \"CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;\""
su - postgres -c "psql -c \"ALTER ROLE $DB_USER SET client_encoding TO 'utf8';\""
su - postgres -c "psql -c \"ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';\""
su - postgres -c "psql -c \"ALTER ROLE $DB_USER SET timezone TO 'UTC';\""

echo "Outline DB credentials:" > /root/outline.creds
echo "DB_USER=$DB_USER" >> /root/outline.creds
echo "DB_PASS=$DB_PASS" >> /root/outline.creds
echo "DB_NAME=$DB_NAME" >> /root/outline.creds

echo "==> Cloning Outline..."
cd /opt
rm -rf outline
git clone https://github.com/outline/outline.git
cd outline

echo "==> Creating .env..."
SECRET_KEY=$(openssl rand -hex 32)
UTILS_SECRET=$(openssl rand -hex 32)
LOCAL_IP=$(hostname -I | awk '{print $1}')

cat <<EOF > /opt/outline/.env
# Base
URL=http://$LOCAL_IP:3000
PORT=3000
SECRET_KEY=$SECRET_KEY
UTILS_SECRET=$UTILS_SECRET
FORCE_HTTPS=false

# Database
DATABASE_URL=postgres://$DB_USER:$DB_PASS@localhost:5432/$DB_NAME

# Redis
REDIS_URL=redis://localhost:6379

# Storage
FILE_STORAGE=local
EOF

echo "==> Installing dependencies & building..."
yarn install --frozen-lockfile
yarn build
yarn db:migrate

echo "==> Setting up systemd service..."
cat <<EOF > /etc/systemd/system/outline.service
[Unit]
Description=Outline Wiki
After=network.target postgresql.service redis.service

[Service]
Type=simple
WorkingDirectory=/opt/outline
ExecStart=/usr/bin/yarn --cwd /opt/outline start
Restart=always
EnvironmentFile=/opt/outline/.env
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now outline

echo "====================================================="
echo " Outline installed successfully!"
echo " Access it at: http://$LOCAL_IP:3000"
echo " DB credentials saved in /root/outline.creds"
echo "====================================================="
