#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Casvt/Kapowarr

APP="Kapowarr"
var_tags="${var_tags:-Arr}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y unzip
  msg_ok "Installed Dependencies"

  setup_uv
  fetch_and_deploy_gh_release "kapowarr" "Casvt/Kapowarr" "tarball"

  msg_info "Installing Kapowarr"
  cd /opt/kapowarr || exit
  $STD uv venv --clear /opt/kapowarr/venv --python 3.12
  $STD uv pip install -r /opt/kapowarr/requirements.txt --python /opt/kapowarr/venv/bin/python3
  msg_ok "Installed Kapowarr"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/kapowarr.service
[Unit]
Description=Kapowarr Daemon
After=syslog.target network.target

[Service]
WorkingDirectory=/opt/kapowarr/
UMask=0002
Restart=on-failure
RestartSec=5
Type=simple
ExecStart=/opt/kapowarr/venv/bin/python3 /opt/kapowarr/Kapowarr.py
KillSignal=SIGINT
TimeoutStopSec=20
SyslogIdentifier=kapowarr

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now kapowarr
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5656${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/systemd/system/kapowarr.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  setup_uv

  if check_for_gh_release "kapowarr" "Casvt/Kapowarr"; then
    msg_info "Stopping Service"
    systemctl stop kapowarr
    msg_ok "Stopped Service"

    msg_info "Creating Backup"
    mv /opt/kapowarr/db /opt/
    msg_ok "Backup Created"

    fetch_and_deploy_gh_release "kapowarr" "Casvt/Kapowarr" "tarball"

    msg_info "Updating Kapowarr"
    mv /opt/db /opt/kapowarr
    cd /opt/kapowarr || exit
    $STD uv pip install -r /opt/kapowarr/requirements.txt --python /opt/kapowarr/venv/bin/python3
    msg_ok "Updated Kapowarr"

    msg_info "Starting Service"
    systemctl start kapowarr
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
