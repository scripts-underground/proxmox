#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# Co-Author: MickLesk (Canbiz)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/evcc-io/evcc

APP="evcc"
var_tags="${var_tags:-solar;ev;automation}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Setting up evcc Repository"
  setup_deb822_repo \
    "evcc-stable" \
    "https://dl.evcc.io/public/evcc/stable/gpg.EAD5D0E07B0EC0FD.key" \
    "https://dl.evcc.io/public/evcc/stable/deb/debian/" \
    "$(get_os_info codename)" \
    "main"
  $STD apt update
  msg_ok "evcc Repository setup sucessfully"

  msg_info "Installing evcc"
  $STD apt install -y evcc
  systemctl enable -q --now evcc
  msg_ok "Installed evcc"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:7070${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if ! command -v evcc > /dev/null 2>&1; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if [[ -f /etc/apt/sources.list.d/evcc-stable.list ]]; then
    setup_deb822_repo \
      "evcc-stable" \
      "https://dl.evcc.io/public/evcc/stable/gpg.EAD5D0E07B0EC0FD.key" \
      "https://dl.evcc.io/public/evcc/stable/deb/debian/" \
      "$(get_os_info codename)" \
      "main"
  fi
  msg_info "Updating evcc LXC"
  $STD apt update
  $STD apt --only-upgrade install -y evcc
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
