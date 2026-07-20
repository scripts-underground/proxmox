#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Lissy93/domain-locker

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Domain-Locker"
var_tags="${var_tags:-Monitoring}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-10240}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y whois
  msg_ok "Installed Dependencies"

  PG_VERSION="17" setup_postgresql
  PG_DB_NAME="domainlocker_db" PG_DB_USER="domainlocker" setup_postgresql_db
  NODE_VERSION="22" setup_nodejs

  fetch_and_deploy_gh_release "domain-locker" "Lissy93/domain-locker" "tarball"

  msg_info "Installing Modules (patience)"
  cd /opt/domain-locker || exit
  $STD npm install
  msg_ok "Installed Modules"

  msg_info "Building Domain-Locker (a lot of patience)"
  cat << EOF > /opt/domain-locker.env
# Database connection
DL_PG_HOST=localhost
DL_PG_PORT=5432
DL_PG_USER=$PG_DB_USER
DL_PG_PASSWORD=$PG_DB_PASS
DL_PG_NAME=$PG_DB_NAME

# Build + Runtime
DL_ENV_TYPE=selfHosted
NITRO_PRESET=node_server
NODE_ENV=production
EOF
  set -a
  source /opt/domain-locker.env
  set +a
  $STD npm run build
  msg_ok "Built Domain-Locker"

  msg_info "Building Database schema"
  export PGPASSWORD="$DL_PG_PASSWORD"
  $STD psql -h "$DL_PG_HOST" -p "$DL_PG_PORT" -U "$DL_PG_USER" -d "$DL_PG_NAME" -f "/opt/domain-locker/db/schema.sql"
  msg_ok "Built Database schema"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/domain-locker.service
[Unit]
Description=Domain-Locker Service
After=network.target

[Service]
EnvironmentFile=/opt/domain-locker.env
WorkingDirectory=/opt/domain-locker
ExecStart=/opt/domain-locker/start.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now domain-locker
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/domain-locker ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  ensure_dependencies whois

  if check_for_gh_release "domain-locker" "Lissy93/domain-locker"; then
    msg_info "Stopping Service"
    systemctl stop domain-locker
    msg_ok "Service stopped"

    PG_VERSION="17" setup_postgresql
    NODE_VERSION="22" setup_nodejs
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "domain-locker" "Lissy93/domain-locker" "tarball"

    msg_info "Installing Modules (patience)"
    cd /opt/domain-locker || exit
    $STD npm install
    msg_ok "Installed Modules"

    msg_info "Building Domain-Locker (a lot of patience)"
    set -a
    source /opt/domain-locker.env
    set +a
    $STD npm run build
    msg_ok "Built Domain-Locker"

    msg_info "Restarting Services"
    systemctl start domain-locker
    msg_ok "Restarted Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
