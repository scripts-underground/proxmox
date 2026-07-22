#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: TuroYT
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/TuroYT/snowshare

# shellcheck disable=SC2034
APP="SnowShare"
var_tags="${var_tags:-file-sharing}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  NODE_VERSION="24" setup_nodejs
  PG_VERSION="17" setup_postgresql
  PG_DB_USER="snowshare" PG_DB_NAME="snowshare" setup_postgresql_db
  fetch_and_deploy_gh_release "snowshare" "TuroYT/snowshare" "tarball"

  msg_info "Installing SnowShare"
  cd /opt/snowshare || exit
  $STD npm ci
  mkdir -p /opt/snowshare_data
  cat << EOF > /opt/snowshare.env
DATABASE_URL="postgresql://$PG_DB_USER:$PG_DB_PASS@localhost:5432/$PG_DB_NAME"
NEXTAUTH_URL="http://localhost:3000"
NEXTAUTH_SECRET="$(openssl rand -base64 32)"
ALLOW_SIGNUP=true
NODE_ENV=production
UPLOAD_DIR=/opt/snowshare_data
EOF
  set -a
  source /opt/snowshare.env
  set +a
  $STD npx prisma generate
  $STD npx prisma migrate deploy
  $STD npm run build
  msg_ok "Installed SnowShare"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/snowshare.service
[Unit]
Description=SnowShare - Modern File Sharing Platform
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/snowshare
EnvironmentFile=/opt/snowshare.env
ExecStart=/usr/bin/npm start
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now snowshare
  msg_ok "Created Service"

  msg_info "Setting up Cleanup Cron Job"
  cat << EOF > /etc/cron.d/snowshare-cleanup
0 2 * * * root cd /opt/snowshare && /usr/bin/npm run cleanup:expired >> /var/log/snowshare-cleanup.log 2>&1
EOF
  msg_ok "Set up Cleanup Cron Job"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/snowshare ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="24" setup_nodejs

  if check_for_gh_release "snowshare" "TuroYT/snowshare"; then
    msg_info "Stopping Service"
    systemctl stop snowshare
    msg_ok "Stopped Service"

    if ! grep -q '^UPLOAD_DIR=' /opt/snowshare.env 2> /dev/null; then
      msg_info "Migrating uploads to persistent directory"
      mkdir -p /opt/snowshare_data
      if [ -d /opt/snowshare/uploads ] && [ -z "$(ls -A /opt/snowshare_data 2> /dev/null)" ]; then
        mv /opt/snowshare/uploads/* /opt/snowshare_data/ 2> /dev/null || true
        mv /opt/snowshare/uploads/.[!.]* /opt/snowshare_data/ 2> /dev/null || true
        rmdir /opt/snowshare/uploads 2> /dev/null || true
      fi
      echo "UPLOAD_DIR=/opt/snowshare_data" >> /opt/snowshare.env
      msg_ok "Migrated uploads to /opt/snowshare_data"
    fi

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "snowshare" "TuroYT/snowshare" "tarball"

    msg_info "Updating Snowshare"
    cd /opt/snowshare || exit
    $STD npm ci
    $STD npx prisma generate
    $STD npm run build
    msg_ok "Updated Snowshare"

    msg_info "Starting Service"
    systemctl start snowshare
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
