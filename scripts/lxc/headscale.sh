#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/juanfont/headscale

APP="Headscale"
var_tags="${var_tags:-networking;vpn}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y curl sudo mc
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "headscale" "juanfont/headscale" "binary"

  msg_info "Creating Service"
  systemctl enable -q --now headscale
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}Headscale API: ${IP}:8080 | headscale-admin: http://${IP}/admin${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /etc/headscale ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if [[ -f /opt/${APP}_version.txt ]]; then
    mv /opt/"${APP}_version.txt" ~/.headscale
  fi

  if check_for_gh_release "headscale" "juanfont/headscale"; then
    msg_info "Stopping Service"
    systemctl stop headscale
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "headscale" "juanfont/headscale" "binary"
    fetch_and_deploy_gh_release "headscale-admin" "GoodiesHQ/headscale-admin" "prebuild" "latest" "/opt/headscale-admin" "admin.zip"

    msg_info "Starting Service"
    systemctl enable -q --now headscale
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
