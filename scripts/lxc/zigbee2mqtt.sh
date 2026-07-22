#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.zigbee2mqtt.io/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Zigbee2MQTT"
var_tags="${var_tags:-smarthome;zigbee;mqtt}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-0}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    git \
    build-essential
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" NODE_MODULE="pnpm@$(curl -fsSL https://raw.githubusercontent.com/Koenkk/zigbee2mqtt/master/package.json | jq -r '.packageManager | split("@")[1]')" setup_nodejs
  fetch_and_deploy_gh_release "Zigbee2MQTT" "Koenkk/zigbee2mqtt" "tarball" "latest" "/opt/zigbee2mqtt"

  msg_info "Setting up Zigbee2MQTT"
  mv /opt/zigbee2mqtt/data/configuration.example.yaml /opt/zigbee2mqtt/data/configuration.yaml
  cd /opt/zigbee2mqtt || exit
  echo "packageImportMethod: hardlink" >> ./pnpm-workspace.yaml
  $STD pnpm install --no-frozen-lockfile
  $STD pnpm build
  msg_ok "Setup Zigbee2MQTT"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/zigbee2mqtt.service
[Unit]
Description=zigbee2mqtt
After=network.target

[Service]
Environment=NODE_ENV=production
ExecStart=/usr/bin/pnpm start
WorkingDirectory=/opt/zigbee2mqtt
StandardOutput=inherit
StandardError=inherit
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now zigbee2mqtt
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9442${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/zigbee2mqtt ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "Zigbee2MQTT" "Koenkk/zigbee2mqtt"; then
    NODE_VERSION="24" NODE_MODULE="pnpm@$(curl -fsSL https://raw.githubusercontent.com/Koenkk/zigbee2mqtt/master/package.json | jq -r '.packageManager | split("@")[1]')" setup_nodejs
    msg_info "Stopping Service"
    systemctl stop zigbee2mqtt
    msg_ok "Stopped Service"

    msg_info "Creating Backup"
    ensure_dependencies zstd
    mkdir -p /opt/backups
    BACKUP_VERSION="$(< "$HOME/.zigbee2mqtt")"
    BACKUP_FILE="/opt/backups/${APP}_backup_${BACKUP_VERSION}.tar.zst"
    $STD tar -cf - -C /opt zigbee2mqtt | zstd -q -o "$BACKUP_FILE"
    ls -t /opt/backups/${APP}_backup_*.tar.zst 2> /dev/null | tail -n +6 | xargs -r rm -f
    msg_ok "Backup Created (${BACKUP_VERSION})"

    create_backup /opt/zigbee2mqtt/data

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "Zigbee2MQTT" "Koenkk/zigbee2mqtt" "tarball" "latest" "/opt/zigbee2mqtt"

    restore_backup

    msg_info "Updating Zigbee2MQTT"
    cd /opt/zigbee2mqtt || exit
    grep -q "^packageImportMethod" ./pnpm-workspace.yaml 2> /dev/null || echo "packageImportMethod: hardlink" >> ./pnpm-workspace.yaml
    $STD pnpm install --frozen-lockfile
    $STD pnpm build
    msg_ok "Updated Zigbee2MQTT"

    msg_info "Starting Service"
    systemctl start zigbee2mqtt
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
