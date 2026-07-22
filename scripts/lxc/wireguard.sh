#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.wireguard.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Wireguard"
var_tags="${var_tags:-network;vpn}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_tun="${var_tun:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git
  msg_ok "Installed Dependencies"

  msg_info "Installing WireGuard"
  $STD apt install -y wireguard wireguard-tools net-tools iptables
  DEBIAN_FRONTEND=noninteractive apt -o Dpkg::Options::="--force-confnew" install -y iptables-persistent &> /dev/null
  $STD netfilter-persistent reload
  msg_ok "Installed WireGuard"

  read -r -p "${TAB3}Would you like to add WGDashboard? <y/N> " prompt
  if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
    git clone -q https://github.com/WGDashboard/WGDashboard.git /etc/wgdashboard

    msg_info "Installing WGDashboard"
    cd /etc/wgdashboard/src || exit
    chmod u+x wgd.sh
    $STD ./wgd.sh install
    . /etc/os-release
    if [ "$VERSION_CODENAME" = "trixie" ]; then
      echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/sysctl.conf
      $STD sysctl -p /etc/sysctl.d/sysctl.conf
    else
      echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
      $STD sysctl -p /etc/sysctl.conf
    fi
    msg_ok "Installed WGDashboard"

    msg_info "Create Example Config for WGDashboard"
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
    msg_ok "Created Example Config for WGDashboard"

    msg_info "Creating Service"
    cat << EOF > /etc/systemd/system/wg-dashboard.service
[Unit]
After=syslog.target network-online.target
Wants=wg-quick.target
ConditionPathIsDirectory=/etc/wireguard

[Service]
Type=forking
PIDFile=/etc/wgdashboard/src/gunicorn.pid
WorkingDirectory=/etc/wgdashboard/src
ExecStart=/etc/wgdashboard/src/wgd.sh start
ExecStop=/etc/wgdashboard/src/wgd.sh stop
ExecReload=/etc/wgdashboard/src/wgd.sh restart
TimeoutSec=120
PrivateTmp=yes
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable -q --now wg-dashboard
    msg_ok "Created Service"
  fi
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access WGDashboard (if installed) using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:10086${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /etc/wireguard ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  ensure_dependencies git

  msg_info "Updating LXC"
  $STD apt update
  $STD apt upgrade -y
  if [[ -d /etc/wgdashboard ]]; then
    sleep 2
    cd /etc/wgdashboard/src || exit
    $STD ./wgd.sh update -y
    $STD ./wgd.sh start
  fi
  msg_ok "Updated LXC"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
