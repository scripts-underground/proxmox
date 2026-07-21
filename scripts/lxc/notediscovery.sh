#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/gamosoft/NoteDiscovery
# shellcheck disable=SC2034
APP="NoteDiscovery"
var_tags="${var_tags:-notes;wiki;knowledge-base}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  setup_uv

  fetch_and_deploy_gh_release "notediscovery" "gamosoft/NoteDiscovery" "tarball"

  msg_info "Installing Dependencies"
  cd /opt/notediscovery || exit
  $STD uv sync --no-dev
  msg_ok "Installed Dependencies"

  msg_info "Configuring NoteDiscovery"
  mkdir -p /opt/notediscovery/data
  msg_ok "Configured NoteDiscovery"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/notediscovery.service
[Unit]
Description=NoteDiscovery Knowledge Base
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/notediscovery
ExecStart=/opt/notediscovery/.venv/bin/python /opt/notediscovery/run.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now notediscovery
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/notediscovery ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "notediscovery" "gamosoft/NoteDiscovery"; then
    msg_info "Stopping Service"
    systemctl stop notediscovery
    msg_ok "Stopped Service"

    create_backup /opt/notediscovery/data /opt/notediscovery/config.yaml

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "notediscovery" "gamosoft/NoteDiscovery" "tarball"

    msg_info "Syncing Dependencies"
    cd /opt/notediscovery || exit
    $STD uv sync --no-dev
    msg_ok "Synced Dependencies"

    restore_backup

    msg_info "Starting Service"
    systemctl start notediscovery
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
