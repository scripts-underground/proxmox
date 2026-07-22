#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://yunohost.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="YunoHost"
var_tags="${var_tags:-os}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_warn "WARNING: This script will run an external installer from a third-party source (https://yunohost.org/)."
  msg_warn "The following code is NOT maintained or audited by our repository."
  msg_warn "If you have any doubts or concerns, please review the installer code before proceeding:"
  msg_custom "${TAB3}${GATEWAY}${BGN}${CL}" "\e[1;34m" "→  https://install.yunohost.org"
  echo
  read -r -p "${TAB3}Do you want to continue? [y/N]: " CONFIRM
  if [[ ! "$CONFIRM" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    msg_error "Aborted by user. No changes have been made."
    exit 10
  fi

  msg_info "Installing Dependencies"
  $STD apt install -y \
    apt-transport-https \
    lsb-release \
    ca-certificates
  msg_ok "Installed Dependencies"

  msg_info "Installing YunoHost (Patience)"
  touch /etc/.pve-ignore.resolv.conf
  curl -fsSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg
  $STD bash <(curl -fsSL https://install.yunohost.org) -a
  msg_ok "Installed YunoHost"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/apt/trusted.gpg.d/php.gpg ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating OS"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated OS"

  msg_info "Updating $APP LXC"
  $STD yunohost tools update
  $STD yunohost tools upgrade system
  $STD yunohost tools upgrade apps
  msg_ok "Updated $APP LXC"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
