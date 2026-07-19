#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.audiobookshelf.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="audiobookshelf"
var_tags="${var_tags:-podcast;audiobook}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y ffmpeg
  msg_ok "Installed Dependencies"

  setup_deb822_repo \
    "audiobookshelf" \
    "https://advplyr.github.io/audiobookshelf-ppa/KEY.gpg" \
    "https://advplyr.github.io/audiobookshelf-ppa" \
    "./"

  msg_info "Setup audiobookshelf"
  $STD apt install -y audiobookshelf
  echo "FFMPEG_PATH=/usr/bin/ffmpeg" >> /etc/default/audiobookshelf
  echo "FFPROBE_PATH=/usr/bin/ffprobe" >> /etc/default/audiobookshelf
  systemctl restart audiobookshelf
  msg_ok "Setup audiobookshelf"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:13378${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/default/audiobookshelf ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating Audiobookshelf"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated Audiobookshelf"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
