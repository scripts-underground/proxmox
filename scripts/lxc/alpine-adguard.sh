#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://adguardhome.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-AdGuard"
var_tags="${var_tags:-alpine;adblock}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-1}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Downloading AdGuard Home"
  $STD curl -fsSL -o "/tmp/AdGuardHome_linux_$(get_system_arch).tar.gz" \
    "https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_$(get_system_arch).tar.gz"
  msg_ok "Downloaded AdGuard Home"

  msg_info "Installing AdGuard Home"
  $STD tar -xzf "/tmp/AdGuardHome_linux_$(get_system_arch).tar.gz" -C /opt
  $STD rm "/tmp/AdGuardHome_linux_$(get_system_arch).tar.gz"
  msg_ok "Installed AdGuard Home"

  msg_info "Creating AdGuard Home Service"
  cat << EOF > /etc/init.d/adguardhome
#!/sbin/openrc-run
name="AdGuardHome"
description="AdGuard Home Service"
command="/opt/AdGuardHome/AdGuardHome"
command_background="yes"
pidfile="/run/adguardhome.pid"
EOF
  $STD chmod +x /etc/init.d/adguardhome
  msg_ok "Created AdGuard Home Service"

  msg_info "Enabling AdGuard Home Service"
  $STD rc-update add adguardhome default
  msg_ok "Enabled AdGuard Home Service"

  msg_info "Starting AdGuard Home"
  $STD rc-service adguardhome start
  msg_ok "Started AdGuard Home"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  msg_info "Updating Alpine Packages"
  $STD apk -U upgrade
  msg_ok "Updated Alpine Packages"

  msg_info "Updating AdGuard Home"
  $STD /opt/AdGuardHome/AdGuardHome --update
  msg_ok "Updated AdGuard Home"

  msg_info "Restarting AdGuard Home"
  $STD rc-service adguardhome restart
  msg_ok "Restarted AdGuard Home"
  msg_ok "Updated successfully!"
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
