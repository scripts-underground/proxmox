#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://readarr.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Readarr"
var_tags="${var_tags:-media;comic;eBook}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y sqlite3 libicu-dev
  msg_ok "Installed Dependencies"

  msg_info "Installing Readarr"
  ARCH=$(uname -m)
  [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
  mkdir -p /var/lib/readarr/
  chmod 775 /var/lib/readarr/
  $STD curl -fsSL "https://readarr.servarr.com/v1/update/develop/updatefile?os=linux&runtime=netcore&arch=${ARCH}" -o /tmp/readarr.tar.gz
  $STD tar -xvzf /tmp/readarr.tar.gz -C /tmp/readarr
  mv /tmp/readarr/Readarr /opt/Readarr
  chmod 775 /opt/Readarr
  rm -rf /tmp/readarr /tmp/readarr.tar.gz
  msg_ok "Installed Readarr"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/readarr.service
[Unit]
Description=Readarr Daemon
After=syslog.target network.target

[Service]
UMask=0002
Type=simple
ExecStart=/opt/Readarr/Readarr -nobrowser -data=/var/lib/readarr/
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl -q daemon-reload
  systemctl enable --now -q readarr
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8787${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /var/lib/readarr/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ${APP} LXC"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated ${APP} LXC"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
