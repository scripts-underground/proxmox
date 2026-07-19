#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Whisparr/Whisparr

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Whisparr"
var_tags="${var_tags:-arr}"
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

  fetch_and_deploy_gh_release "Whisparr" "Whisparr/Whisparr" "prebuild" "latest" "/opt/Whisparr" "Whisparr.*.linux-$(get_system_arch).tar.gz"

  msg_info "Configuring Whisparr"
  mkdir -p /var/lib/whisparr/
  chmod 775 /var/lib/whisparr/
  chmod 775 /opt/Whisparr
  msg_ok "Configured Whisparr"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/whisparr.service
[Unit]
Description=Whisparr Daemon
After=syslog.target network.target

[Service]
UMask=0002
Type=simple
ExecStart=/opt/Whisparr/Whisparr -nobrowser -data=/var/lib/whisparr/
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now whisparr
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:6969${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /var/lib/whisparr/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_custom "🚀" "${GN}" "${APP} offers a built-in updater. Please use it."
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
