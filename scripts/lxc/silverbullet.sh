#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Dominik Siebel (dsiebel)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://silverbullet.md | Github: https://github.com/silverbulletmd/silverbullet

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Silverbullet"
var_tags="${var_tags:-notes}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_gh_release "silverbullet" "silverbulletmd/silverbullet" "prebuild" "latest" "/opt/silverbullet/bin" "silverbullet-server-linux-$(uname -m).zip"

  mkdir -p /opt/silverbullet/space

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/silverbullet.service
[Unit]
Description=Silverbullet Daemon
After=syslog.target network.target

[Service]
User=root
Type=simple
ExecStart=/opt/silverbullet/bin/silverbullet --hostname 0.0.0.0 --port 3000 /opt/silverbullet/space
WorkingDirectory=/opt/silverbullet
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable --now -q silverbullet
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/silverbullet ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "silverbullet" "silverbulletmd/silverbullet"; then
    msg_info "Stopping Service"
    systemctl stop silverbullet
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "silverbullet" "silverbulletmd/silverbullet" "prebuild" "latest" "/opt/silverbullet/bin" "silverbullet-server-linux-$(uname -m).zip"

    msg_info "Starting Service"
    systemctl start silverbullet
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
