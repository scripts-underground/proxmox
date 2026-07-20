#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: bvdberg01
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://listmonk.app/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="listmonk"
var_tags="${var_tags:-newsletter}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  setup_postgresql
  PG_DB_NAME="listmonk" PG_DB_USER="listmonk" setup_postgresql_db

  msg_info "Installing Dependencies"
  $STD apt install -y curl
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "listmonk" "knadh/listmonk" "prebuild" "latest" "/opt/listmonk" "listmonk_*_linux_$(get_system_arch).tar.gz"

  msg_info "Configuring listmonk"
  cd /opt/listmonk || exit
  $STD ./listmonk --new-config > /opt/listmonk/config.toml
  sed -i "s/^address = .*/address = \"0.0.0.0:9000\"/" /opt/listmonk/config.toml
  sed -i "s/^user = .*/user = \"${PG_DB_USER}\"/" /opt/listmonk/config.toml
  sed -i "s/^password = .*/password = \"${PG_DB_PASS}\"/" /opt/listmonk/config.toml
  sed -i "s/^database = .*/database = \"${PG_DB_NAME}\"/" /opt/listmonk/config.toml
  msg_ok "Configured listmonk"

  msg_info "Running Database Migrations"
  $STD /opt/listmonk/listmonk --upgrade --yes --config /opt/listmonk/config.toml
  msg_ok "Ran Database Migrations"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/listmonk.service
[Unit]
Description=listmonk Service
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/listmonk
ExecStart=/opt/listmonk/listmonk --config /opt/listmonk/config.toml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now listmonk
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/listmonk.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "listmonk" "knadh/listmonk"; then
    msg_info "Stopping Service"
    systemctl stop listmonk
    msg_ok "Stopped Service"

    msg_info "Backing up data"
    mv /opt/listmonk/ /opt/listmonk-backup
    msg_ok "Backed up data"

    fetch_and_deploy_gh_release "listmonk" "knadh/listmonk" "prebuild" "latest" "/opt/listmonk" "listmonk_*_linux_$(get_system_arch).tar.gz"

    msg_info "Configuring listmonk"
    mv /opt/listmonk-backup/config.toml /opt/listmonk/config.toml
    mv /opt/listmonk-backup/uploads /opt/listmonk/uploads 2> /dev/null || true
    $STD /opt/listmonk/listmonk --upgrade --yes --config /opt/listmonk/config.toml
    rm -rf /opt/listmonk-backup/
    msg_ok "Configured listmonk"

    msg_info "Starting Service"
    systemctl start listmonk
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
