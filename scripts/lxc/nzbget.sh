#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck | Co-Author: havardthom
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://nzbget.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="NZBGet"
var_tags="${var_tags:-usenet;downloader}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  setup_nonfree

  msg_info "Installing Dependencies"
  $STD apt install -y \
    par2 \
    unrar
  msg_ok "Installed Dependencies"

  msg_info "Installing NZBGet"
  setup_deb822_repo \
    "nzbgetcom" \
    "https://nzbgetcom.github.io/nzbgetcom.asc" \
    "https://nzbgetcom.github.io/deb" \
    "stable"
  $STD apt install -y nzbget
  sed -i "s|SevenZipCmd=7zz|SevenZipCmd=7z|g" /var/lib/nzbget/nzbget.conf
  systemctl restart nzbget
  msg_ok "Installed NZBGet"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:6789${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /lib/systemd/system/nzbget.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if ! command -v unrar &> /dev/null; then
    setup_nonfree
    $STD apt install -y unrar

    if grep -q "UnrarCmd=unrar-free" /var/lib/nzbget/nzbget.conf; then
      sed -i "s|UnrarCmd=unrar-free|UnrarCmd=unrar|g" /var/lib/nzbget/nzbget.conf
    fi
  fi

  msg_info "Updating NZBGet"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated NZBGet"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
