#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://getqui.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Qui"
var_tags="${var_tags:-torrent}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  ARCH=$(uname -m)
  [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"

  fetch_and_deploy_gh_release "qui" "autobrr/qui" "prebuild" "latest" "/usr/local/bin" "qui_*_linux_${ARCH}.tar.gz"

  msg_info "Creating Qui Service"
  cat << EOF > /etc/systemd/system/qui.service
[Unit]
Description=Qui - qBittorrent Web UI
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/qui serve
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now qui
  msg_ok "Created Qui Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:7476${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /usr/local/bin/qui ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "Qui" "autobrr/qui"; then
    msg_info "Stopping Service"
    systemctl stop qui
    msg_ok "Stopped Service"

    ARCH=$(uname -m)
    [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
    fetch_and_deploy_gh_release "qui" "autobrr/qui" "prebuild" "latest" "/tmp/qui" "qui_*_linux_${ARCH}.tar.gz"

    msg_info "Updating qui"
    mv /tmp/qui/qui /usr/local/bin/qui
    chmod +x /usr/local/bin/qui
    rm -rf /tmp/qui
    msg_ok "Updated qui"

    msg_info "Starting Service"
    systemctl start qui
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
