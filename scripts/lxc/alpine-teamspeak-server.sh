#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tremor021 (Slaviša Arežina)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.teamspeak.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-TeamSpeak-Server"
var_tags="${var_tags:-alpine;communication}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apk add --no-cache curl jq ca-certificates openssl
  msg_ok "Installed Dependencies"

  msg_info "Installing TeamSpeak Server"
  RELEASE=$(curl -fsSL "https://api.github.com/repos/mkoelle/teamspeak-server-api/releases/latest" | jq -r '.tag_name' | sed 's/^v//')
  [ -z "$RELEASE" ] && RELEASE=$(curl -fsSL "https://files.teamspeak-services.com/releases/server/" | grep -oP 'href="\K[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)
  mkdir -p /opt/teamspeak-server
  cd /opt/teamspeak-server || exit
  ARCH=$(uname -m)
  [ "$ARCH" = "aarch64" ] && ARCH="arm64"
  curl -fsSL "https://files.teamspeak-services.com/releases/server/${RELEASE}/teamspeak3-server_linux_${ARCH}-${RELEASE}.tar.bz2" -o ts3server.tar.bz2
  tar xf ts3server.tar.bz2 --strip-components=1
  mkdir -p logs data lib
  mv *.so lib 2> /dev/null || true
  touch data/ts3server.sqlitedb data/query_ip_blacklist.txt data/query_ip_whitelist.txt .ts3server_license_accepted
  echo "${RELEASE}" > ~/.teamspeak-server
  msg_ok "Installed TeamSpeak Server v${RELEASE}"

  msg_info "Enabling TeamSpeak Server Service"
  cat << EOF > /etc/init.d/teamspeak
#!/sbin/openrc-run
name="TeamSpeak Server"
description="TeamSpeak 3 Server"
command="/opt/teamspeak-server/ts3server_startscript.sh"
command_args="start"
output_log="/var/log/teamspeak.out.log"
error_log="/var/log/teamspeak.err.log"
command_background=true
pidfile="/run/teamspeak-server.pid"
directory="/opt/teamspeak-server"
depend() {
    need net
    use dns
}
EOF
  chmod +x /etc/init.d/teamspeak
  $STD rc-update add teamspeak default
  msg_ok "Enabled TeamSpeak Server Service"
  msg_info "Starting TeamSpeak Server"
  $STD service teamspeak start
  msg_ok "Started TeamSpeak Server"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} TeamSpeak Server is running. Connect using your TeamSpeak client.${CL}"
}

function update_script() {
  header_info
  if [[ ! -d /opt/teamspeak-server ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating $APP LXC"
  $STD apk -U upgrade
  msg_ok "Updated $APP LXC"
  msg_info "Restarting TeamSpeak Server"
  rc-service teamspeak restart
  msg_ok "Restarted TeamSpeak Server"
  msg_ok "Updated successfully!"
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
