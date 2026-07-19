#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.wireguard.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-Wireguard"
var_tags="${var_tags:-alpine;networking}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing WireGuard"
  $STD apk add wireguard-tools
  dphys-swapfile swapoff 2> /dev/null || true
  $STD apk add wireguard-virt
  dphys-swapfile swapon 2> /dev/null || true
  msg_ok "Installed WireGuard"

  if [ ! -f /etc/wireguard/wg0.conf ]; then
    if [ -d /etc/wireguard ]; then
      systemctl stop wg-quick@wg0 2> /dev/null || true
    fi
    mkdir -p /etc/wireguard
    $STD apk add iptables
    ln -s /etc/init.d/wg-quick /etc/init.d/wg-quick.wg0 2> /dev/null || true
  fi
  private_key=$(wg genkey)
  cat << EOF > /etc/wireguard/wg0.conf
[Interface]
PrivateKey = ${private_key}
Address = 10.0.0.1/24
SaveConfig = true
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE;
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE;
ListenPort = 51820
EOF
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
  $STD rc-update add sysctl
  $STD sysctl -p /etc/sysctl.conf
  msg_ok "Installed WireGuard"

  read -rp "${TAB3}Do you want to install WGDashboard? (y/N): " INSTALL_WGD
  if [[ "$INSTALL_WGD" =~ ^[Yy]$ ]]; then
    msg_info "Installing additional dependencies for WGDashboard"
    $STD apk add --no-cache python3 py3-pip git sudo musl-dev linux-headers gcc python3-dev
    msg_ok "Installed additional dependencies for WGDashboard"
    msg_info "Installing WGDashboard"
    git clone https://github.com/donaldzou/WGDashboard.git /opt/wgdashboard
    chmod +x /opt/wgdashboard/src/wgd.sh
    cd /opt/wgdashboard/src || exit
    $STD pip install -r requirements.txt
    chmod -R 755 /opt/wgdashboard
    msg_ok "Installed WGDashboard"
    msg_info "Starting WGDashboard"
    $STD python3 /opt/wgdashboard/src/wgd.py --background
    msg_ok "Started WGDashboard"
  fi
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} WireGuard is configured with a new private key.${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}WGDashboard: http://${IP}:10086 (if installed)${CL}"
}

function update_script() {
  header_info
  msg_info "Updating $APP LXC"
  $STD apk -U upgrade
  msg_ok "Updated $APP LXC"
  msg_ok "Updated successfully!"
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
