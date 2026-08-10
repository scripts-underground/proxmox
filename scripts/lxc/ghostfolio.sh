#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: lucasfell
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://ghostfol.io/

# shellcheck disable=SC2034
APP="Ghostfolio"
var_tags="${var_tags:-finance;investment}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_git_repo="${var_lxc_git_repo:-ghostfolio/ghostfolio}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    openssl \
    ca-certificates \
    redis-server
  msg_ok "Installed Dependencies"

  PG_VERSION="17" setup_postgresql
  NODE_VERSION="24" setup_nodejs

  msg_info "Setting up Database"
  PG_DB_NAME="ghostfolio" PG_DB_USER="ghostfolio" PG_DB_SCHEMA_PERMS="true" setup_postgresql_db
  REDIS_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  ACCESS_TOKEN_SALT=$(openssl rand -base64 32)
  JWT_SECRET_KEY=$(openssl rand -base64 32)
  cat << EOF > ~/ghostfolio.creds
Ghostfolio Credentials
Redis Password: $REDIS_PASS
Access Token Salt: $ACCESS_TOKEN_SALT
JWT Secret Key: $JWT_SECRET_KEY
EOF
  msg_ok "Set up Database"

  fetch_and_deploy_gh_release "ghostfolio" "$var_lxc_git_repo" "tarball" "latest" "/opt/ghostfolio"

  msg_info "Setup Ghostfolio"
  sed -i "s/# requirepass foobared/requirepass $REDIS_PASS/" /etc/redis/redis.conf
  systemctl restart redis-server
  cd /opt/ghostfolio || exit
  $STD npm ci
  $STD npm run build:production
  msg_ok "Built Ghostfolio"

  echo -e ""
  msg_custom "🪙" "$YW" "CoinGecko API keys are optional but provide better cryptocurrency data."
  msg_custom "🪙" "$YW" "You can skip this and add them later by editing /opt/ghostfolio/.env"
  echo -e ""
  read -rp "${TAB3}CoinGecko Demo API key (press Enter to skip): " COINGECKO_DEMO_KEY
  read -rp "${TAB3}CoinGecko Pro API key (press Enter to skip): " COINGECKO_PRO_KEY

  msg_info "Setting up Environment"
  cat << EOF > /opt/ghostfolio/.env
DATABASE_URL=postgresql://$PG_DB_USER:$PG_DB_PASS@localhost:5432/$PG_DB_NAME?connect_timeout=300
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=$REDIS_PASS
ACCESS_TOKEN_SALT=$ACCESS_TOKEN_SALT
JWT_SECRET_KEY=$JWT_SECRET_KEY
NODE_ENV=production
PORT=3333
HOST=0.0.0.0
TZ=Etc/UTC
EOF

  if [[ -n "${COINGECKO_DEMO_KEY:-}" ]]; then
    echo "API_KEY_COINGECKO_DEMO=$COINGECKO_DEMO_KEY" >> /opt/ghostfolio/.env
  fi

  if [[ -n "${COINGECKO_PRO_KEY:-}" ]]; then
    echo "API_KEY_COINGECKO_PRO=$COINGECKO_PRO_KEY" >> /opt/ghostfolio/.env
  fi
  msg_ok "Set up Environment"

  msg_info "Running Database Migrations"
  cd /opt/ghostfolio || exit
  $STD npx prisma migrate deploy
  $STD npx prisma db seed
  msg_ok "Database Migrations Complete"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/ghostfolio.service
[Unit]
Description=Ghostfolio Investment Tracker
After=network.target postgresql.service redis-server.service
Wants=postgresql.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/ghostfolio/dist/apps/api
Environment=NODE_ENV=production
EnvironmentFile=/opt/ghostfolio/.env
ExecStart=/usr/bin/node main.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

  systemctl enable -q --now ghostfolio
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3333${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/ghostfolio/dist/apps/api/main.js ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "ghostfolio" "$var_lxc_git_repo"; then
    msg_info "Stopping Service"
    systemctl stop ghostfolio
    msg_ok "Stopped Service"

    msg_info "Creating Backup"
    tar -czf "/opt/ghostfolio_backup_$(date +%F).tar.gz" \
      -C /opt \
      --exclude="ghostfolio/node_modules" \
      --exclude="ghostfolio/dist" \
      ghostfolio
    mv /opt/ghostfolio/.env /opt/env.backup
    msg_ok "Backup Created"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "ghostfolio" "$var_lxc_git_repo" "tarball" "latest" "/opt/ghostfolio"

    msg_info "Updating Ghostfolio"
    mv /opt/env.backup /opt/ghostfolio/.env
    sed -i -E '/^DATABASE_URL=/ s/[?&]sslmode=prefer//g' /opt/ghostfolio/.env
    cd /opt/ghostfolio || exit
    $STD npm ci
    $STD npm run build:production
    $STD npx prisma migrate deploy
    msg_ok "Updated Ghostfolio"

    msg_info "Starting Service"
    systemctl start ghostfolio
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
