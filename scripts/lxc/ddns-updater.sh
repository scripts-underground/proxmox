#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: reptil1990
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/qdm12/ddns-updater

APP="DDNS-Updater"
var_tags="${var_tags:-network}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_gh_release "ddns-updater" "qdm12/ddns-updater" "singlefile" "latest" "/opt/ddns-updater" "ddns-updater_*_linux_amd64"

  msg_info "Configuring DDNS-Updater"
  mkdir -p /opt/ddns-updater/data
  cat << EOF > /opt/ddns-updater/data/config.json
{
  "settings": [
    {
      "provider": "namecheap",
      "domain": "example.com",
      "password": "e5322165c1d74692bfa6d807100c0310"
    }
  ]
}
EOF
  msg_ok "Configured DDNS-Updater"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/ddns-updater.service
[Unit]
Description=DDNS-Updater
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=/bin/bash -c 'for i in \$(seq 1 30); do curl -sf --max-time 5 https://1.1.1.1 >/dev/null 2>&1 && break || sleep 2; done'
ExecStart=/opt/ddns-updater/ddns-updater
Environment=DATADIR=/opt/ddns-updater/data
Environment=LISTENING_ADDRESS=:8000
Environment=LOG_LEVEL=info
Environment=PERIOD=5m
WorkingDirectory=/opt/ddns-updater
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now ddns-updater
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/ddns-updater ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "ddns-updater" "qdm12/ddns-updater"; then
    msg_info "Stopping Service"
    systemctl stop ddns-updater
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    cp -r /opt/ddns-updater/data /opt/ddns-updater_data_backup
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "ddns-updater" "qdm12/ddns-updater" "singlefile" "latest" "/opt/ddns-updater" "ddns-updater_*_linux_amd64"

    msg_info "Restoring Data"
    cp -r /opt/ddns-updater_data_backup/. /opt/ddns-updater/data/
    rm -rf /opt/ddns-updater_data_backup
    msg_ok "Restored Data"

    msg_info "Starting Service"
    systemctl start ddns-updater
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
