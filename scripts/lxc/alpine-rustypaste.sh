#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/orhun/rustypaste

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-RustyPaste"
var_tags="${var_tags:-alpine;pastebin;storage}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing RustyPaste"
  $STD apk add rustypaste
  msg_ok "Installed RustyPaste"

  cat << 'EOF' > /etc/init.d/rustypaste
name="rustypaste"
description="RustyPaste - A minimal file upload/pastebin service"
command="/usr/bin/rustypaste"
command_user="root"
command_background=true
pidfile="/run/${RC_SVCNAME}.pid"
directory="/var/lib/rustypaste"
depend() {
    need net
    after firewall
}
start_pre() {
    export CONFIG=/etc/rustypaste/config.toml
    checkpath --directory --owner root:root --mode 0755 /var/lib/rustypaste
}
EOF
  chmod +x /etc/init.d/rustypaste
  $STD rc-update add rustypaste default
  $STD rc-service rustypaste start
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
}

function update_script() {
  header_info
  msg_info "Updating $APP LXC"
  $STD apk -U upgrade
  msg_ok "Updated $APP LXC"
  msg_info "Restarting RustyPaste"
  rc-service rustypaste restart
  msg_ok "Restarted RustyPaste"
  msg_ok "Updated successfully!"
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
