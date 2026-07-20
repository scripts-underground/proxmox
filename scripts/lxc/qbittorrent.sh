#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster) | Co-Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.qbittorrent.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="qBittorrent"
var_tags="${var_tags:-torrent}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  local arch
  arch=$(uname -m)

  msg_info "Installing qBittorrent"
  fetch_and_deploy_gh_release "qbittorrent" "userdocs/qbittorrent-nox-static" "singlefile" "latest" "/opt/qbittorrent" "${arch}-qbittorrent-nox"

  mv /opt/qbittorrent/qbittorrent /opt/qbittorrent/qbittorrent-nox
  mkdir -p ~/.config/qBittorrent/
  cat << EOF > ~/.config/qBittorrent/qBittorrent.conf
[LegalNotice]
Accepted=true

[Preferences]
WebUI\Password_PBKDF2="@ByteArray(amjeuVrF3xRbgzqWQmes5A==:XK3/Ra9jUmqUc4RwzCtrhrkQIcYczBl90DJw2rT8DFVTss4nxpoRhvyxhCf87ahVE3SzD8K9lyPdpyUCfmVsUg==)"
WebUI\Port=8090
WebUI\UseUPnP=false
WebUI\Username=admin

[Network]
PortForwardingEnabled=false
EOF
  msg_ok "Installed qBittorrent"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/qbittorrent-nox.service
[Unit]
Description=qBittorrent client
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/qbittorrent/qbittorrent-nox
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now qbittorrent-nox
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8090${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/systemd/system/qbittorrent-nox.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if [[ ! -f ~/.qbittorrent ]]; then
    msg_error "Please create new qBittorrent LXC. Updating from v4.x to v5.x is not supported!"
    exit
  fi

  if check_for_gh_release "qbittorrent" "userdocs/qbittorrent-nox-static"; then
    msg_info "Stopping Service"
    systemctl stop qbittorrent-nox
    msg_ok "Stopped Service"

    local arch
    arch=$(uname -m)
    rm -f /opt/qbittorrent/qbittorrent-nox
    fetch_and_deploy_gh_release "qbittorrent" "userdocs/qbittorrent-nox-static" "singlefile" "latest" "/opt/qbittorrent" "${arch}-qbittorrent-nox"
    mv /opt/qbittorrent/qbittorrent /opt/qbittorrent/qbittorrent-nox

    msg_info "Starting Service"
    systemctl start qbittorrent-nox
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
