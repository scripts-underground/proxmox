#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.openmediavault.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="OMV"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt update
  $STD apt install -y curl gnupg
  msg_ok "Installed Dependencies"

  msg_info "Installing OpenMediaVault (Patience)"
  curl -fsSL "https://packages.openmediavault.org/public/archive.key" | gpg --dearmor > "/etc/apt/trusted.gpg.d/openmediavault-archive-keyring.gpg"
  cat << EOF > /etc/apt/sources.list.d/openmediavault.list
deb [signed-by=/etc/apt/trusted.gpg.d/openmediavault-archive-keyring.gpg] http://packages.openmediavault.org/public sandworm main
EOF
  export LANG=C.UTF-8
  export DEBIAN_FRONTEND=noninteractive
  export APT_LISTCHANGES_FRONTEND=none
  $STD apt update
  $STD apt -y --auto-remove --show-upgraded --allow-downgrades --allow-change-held-packages --no-install-recommends --option DPkg::Options::="--force-confdef" --option DPkg::Options::="--force-confold" install openmediavault-keyring openmediavault &> /dev/null
  omv-confdbadm populate &> /dev/null
  msg_ok "Installed OpenMediaVault"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/apt/sources.list.d/openmediavault.list ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP} LXC"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated Successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime — shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
