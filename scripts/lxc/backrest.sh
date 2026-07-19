#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: ksad (enirys31)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://garethgeorge.github.io/backrest/
# shellcheck disable=SC2034
APP="Backrest"
var_tags="${var_tags:-backup}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
function install_script() {
  ARCH=$(uname -m)
  [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
  fetch_and_deploy_gh_release "backrest" "garethgeorge/backrest" "prebuild" "latest" "/opt/backrest/bin" "backrest_Linux_${ARCH}.tar.gz"
  msg_info "Creating Service"
  cat << EOF > /opt/backrest/.env
BACKREST_PORT=9898
BACKREST_CONFIG=/opt/backrest/config/config.json
BACKREST_DATA=/opt/backrest/data
XDG_CACHE_HOME=/opt/backrest/cache
EOF
  cat << EOF > /etc/systemd/system/backrest.service
[Unit]
Description=Backrest
After=network.target
[Service]
Type=simple
ExecStart=/opt/backrest/bin/backrest
EnvironmentFile=/opt/backrest/.env
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now backrest
  msg_ok "Created Service"
}
function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9898${CL}"
}
function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/backrest ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "backrest" "garethgeorge/backrest"; then
    msg_info "Stopping Service"
    systemctl stop backrest
    msg_ok "Stopped Service"
    ARCH=$(uname -m)
    [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
    fetch_and_deploy_gh_release "backrest" "garethgeorge/backrest" "prebuild" "latest" "/opt/backrest/bin" "backrest_Linux_${ARCH}.tar.gz"
    msg_info "Starting Service"
    systemctl start backrest
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
