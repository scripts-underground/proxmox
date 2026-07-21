#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://umami.is/

# shellcheck disable=SC2034
APP="Umami"
var_tags="${var_tags:-analytics}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-12}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  NODE_VERSION="22" NODE_MODULE="pnpm@latest" setup_nodejs
  PG_VERSION="17" setup_postgresql
  PG_DB_NAME="umamidb" PG_DB_USER="umami" setup_postgresql_db

  fetch_and_deploy_gh_release "umami" "umami-software/umami" "tarball"

  msg_info "Configuring Umami"
  cd /opt/umami || exit
  $STD pnpm install
  echo -e "DATABASE_URL=postgresql://$PG_DB_USER:$PG_DB_PASS@localhost:5432/$PG_DB_NAME" >> /opt/umami/.env
  $STD pnpm run build
  msg_ok "Configured Umami"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/umami.service
[Unit]
Description=Umami Analytics Service
After=network.target

[Service]
Type=simple
Restart=always
User=root
WorkingDirectory=/opt/umami
ExecStart=/usr/bin/pnpm run start

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now umami
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/umami ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "umami" "umami-software/umami"; then
    msg_info "Stopping Service"
    systemctl stop umami
    msg_ok "Stopped Service"

    mv /opt/umami/.env /opt/.env.bak
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "umami" "umami-software/umami" "tarball"
    mv /opt/.env.bak /opt/umami/.env

    msg_info "Updating Umami"
    cd /opt/umami || exit
    $STD pnpm install
    $STD pnpm run build
    msg_ok "Updated Umami"

    msg_info "Starting Service"
    systemctl start umami
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
