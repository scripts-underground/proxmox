#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tremor021 (Slaviša Arežina)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://teamspeak.com/en/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Teamspeak-Server"
var_tags="${var_tags:-voice;communication}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Setting up Teamspeak Server"
  RELEASE=$(curl -fsSL https://teamspeak.com/en/downloads/#server | grep -oP 'teamspeak3-server_linux_amd64-\K[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  curl -fsSL "https://files.teamspeak-services.com/releases/server/${RELEASE}/teamspeak3-server_linux_amd64-${RELEASE}.tar.bz2" -o ts3server.tar.bz2
  tar -xf ./ts3server.tar.bz2
  mv teamspeak3-server_linux_amd64/ /opt/teamspeak-server/
  touch /opt/teamspeak-server/.ts3server_license_accepted
  rm -f ~/ts3server.tar.bz*
  echo "${RELEASE}" > ~/.teamspeak-server
  msg_ok "Setup Teamspeak Server"

  msg_info "Creating service"
  cat << EOF > /etc/systemd/system/teamspeak-server.service
[Unit]
Description=TeamSpeak3 Server
Wants=network-online.target
After=network.target

[Service]
WorkingDirectory=/opt/teamspeak-server
User=root
Type=forking
ExecStart=/opt/teamspeak-server/ts3server_startscript.sh start
ExecStop=/opt/teamspeak-server/ts3server_startscript.sh stop
ExecReload=/opt/teamspeak-server/ts3server_startscript.sh restart
Restart=always
RestartSec=15

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now teamspeak-server
  msg_ok "Created service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}${IP}:9987${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/teamspeak-server ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(curl -fsSL https://teamspeak.com/en/downloads/#server | grep -oP 'teamspeak3-server_linux_amd64-\K[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  if [[ "${RELEASE}" != "$(cat ~/.teamspeak-server 2> /dev/null)" ]] || [[ ! -f ~/.teamspeak-server ]]; then
    msg_info "Stopping Service"
    systemctl stop teamspeak-server
    msg_ok "Stopped Service"

    msg_info "Updating Teamspeak Server"
    curl -fsSL "https://files.teamspeak-services.com/releases/server/${RELEASE}/teamspeak3-server_linux_amd64-${RELEASE}.tar.bz2" -o ts3server.tar.bz2
    tar -xf ./ts3server.tar.bz2
    cp -ru teamspeak3-server_linux_amd64/* /opt/teamspeak-server/
    rm -f ~/ts3server.tar.bz*
    echo "${RELEASE}" > ~/.teamspeak-server
    msg_ok "Updated Teamspeak Server"

    msg_info "Starting Service"
    systemctl start teamspeak-server
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  else
    msg_ok "Already up to date"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
