#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Giovanni Pellerano (evilaliv3)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/globaleaks/globaleaks-whistleblowing-software
# shellcheck disable=SC2034
APP="GlobaLeaks"
var_tags="${var_tags:-whistleblowing-software}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
function install_script() {
  msg_info "Setting Up GlobaLeaks Repository"
  DISTRO_CODENAME="$(awk -F= '/^VERSION_CODENAME=/{print $2}' /etc/os-release)"
  curl -fsSL https://deb.globaleaks.org/globaleaks.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/globaleaks.gpg
  echo "deb [signed-by=/etc/apt/trusted.gpg.d/globaleaks.gpg] https://deb.globaleaks.org $DISTRO_CODENAME/" > /etc/apt/sources.list.d/globaleaks.list
  echo 'APPARMOR_SANDBOXING=0' > /etc/default/globaleaks
  msg_ok "Set Up GlobaLeaks Repository"
  msg_info "Installing GlobaLeaks"
  $STD apt update
  $STD apt -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install globaleaks
  msg_ok "Installed GlobaLeaks"
}
function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}https://${IP}${CL}"
}
function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /usr/sbin/globaleaks ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating $APP"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated $APP"
  exit
}
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
