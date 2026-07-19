#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://caddyserver.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Caddy"
var_tags="${var_tags:-webserver}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    debian-keyring \
    debian-archive-keyring \
    apt-transport-https
  msg_ok "Installed Dependencies"

  msg_info "Installing Caddy"
  setup_deb822_repo \
    "caddy" \
    "https://dl.cloudsmith.io/public/caddy/stable/gpg.key" \
    "https://dl.cloudsmith.io/public/caddy/stable/deb/debian" \
    "any-version"
  $STD apt install -y caddy
  msg_ok "Installed Caddy"

  read -r -p "${TAB3}Would you like to install xCaddy Addon? <y/N> " prompt
  if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
    setup_go
    fetch_and_deploy_gh_release "xcaddy" "caddyserver/xcaddy" "binary"

    msg_info "Setup xCaddy"
    $STD apt install -y git
    $STD xcaddy build
    msg_ok "Setup xCaddy"
  fi
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:80${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /etc/caddy ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating Caddy LXC"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated Caddy LXC"

  if command -v xcaddy > /dev/null 2>&1; then
    if check_for_gh_release "xcaddy" "caddyserver/xcaddy"; then
      setup_go
      fetch_and_deploy_gh_release "xcaddy" "caddyserver/xcaddy" "binary"

      msg_info "Updating xCaddy"
      $STD xcaddy build
      msg_ok "Updated xCaddy"
    fi
  fi
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
