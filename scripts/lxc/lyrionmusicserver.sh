#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Omar Minaya
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://lyrion.org/getting-started/

# shellcheck disable=SC2034
APP="Lyrion Music Server"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-3}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y ca-certificates
  msg_ok "Installed Dependencies"

  msg_info "Setup Lyrion Music Server"
  if [[ "$(get_system_arch)" == "arm64" ]]; then
    DEB_ARCH="arm"
  else
    DEB_ARCH="amd64"
  fi
  DEB_URL=$(curl_with_retry 'https://lyrion.org/getting-started/' | grep -oP "<a\s[^>]*href=\"\K[^\"]*${DEB_ARCH}\.deb(?=\"[^>]*>)" | head -n 1)
  RELEASE=$(echo "$DEB_URL" | grep -oP "lyrionmusicserver_\K[0-9.]+(?=_${DEB_ARCH}\.deb)")
  DEB_FILE="/tmp/lyrionmusicserver_${RELEASE}_${DEB_ARCH}.deb"
  curl_with_retry "$DEB_URL" "$DEB_FILE"
  $STD apt install "$DEB_FILE" -y
  rm -f "$DEB_FILE"
  echo "${RELEASE}" > "/opt/lyrion_version.txt"
  msg_ok "Setup Lyrion Music Server v${RELEASE}"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:9000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /lib/systemd/system/lyrionmusicserver.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if [[ "$(get_system_arch)" == "arm64" ]]; then
    DEB_ARCH="arm"
  else
    DEB_ARCH="amd64"
  fi
  DEB_URL=$(curl_with_retry 'https://lyrion.org/getting-started/' | grep -oP "<a\s[^>]*href=\"\K[^\"]*${DEB_ARCH}\.deb(?=\"[^>]*>)" | head -n 1)
  RELEASE=$(echo "$DEB_URL" | grep -oP "lyrionmusicserver_\K[0-9.]+(?=_${DEB_ARCH}\.deb)")
  DEB_FILE="/tmp/lyrionmusicserver_${RELEASE}_${DEB_ARCH}.deb"
  if [[ ! -f /opt/lyrion_version.txt ]] || [[ ${RELEASE} != "$(cat /opt/lyrion_version.txt)" ]]; then
    msg_info "Updating $APP to ${RELEASE}"
    curl_with_retry "$DEB_URL" "$DEB_FILE"
    $STD apt install "$DEB_FILE" -y
    systemctl restart lyrionmusicserver
    rm -f "$DEB_FILE"
    echo "${RELEASE}" > /opt/lyrion_version.txt
    msg_ok "Updated $APP to ${RELEASE}"
    msg_ok "Updated successfully!"
  else
    msg_ok "$APP is already up to date (${RELEASE})"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
