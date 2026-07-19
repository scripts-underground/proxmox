#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/daya0576/beaverhabits

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="BeaverHabits"
var_tags="${var_tags:-habits;tracking;productivity}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  PYTHON_VERSION="3.14" setup_uv
  fetch_and_deploy_gh_release "beaverhabits" "daya0576/beaverhabits" "tarball"

  msg_info "Installing Dependencies"
  cd /opt/beaverhabits || exit
  $STD uv sync --no-dev
  msg_ok "Installed Dependencies"

  msg_info "Configuring BeaverHabits"
  mkdir -p /opt/beaverhabits/.user
  msg_ok "Configured BeaverHabits"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/beaverhabits.service
[Unit]
Description=BeaverHabits Habit Tracker
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/beaverhabits
Environment=HABITS_STORAGE=USER_DISK
Environment=NICEGUI_STORAGE_PATH=/opt/beaverhabits/.user/.nicegui
ExecStart=/opt/beaverhabits/.venv/bin/gunicorn beaverhabits.main:app --bind 0.0.0.0:8080 -w 1 -k uvicorn_worker.UvicornWorker --max-requests 10000 --log-level info
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now beaverhabits
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8080/register${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/beaverhabits ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "beaverhabits" "daya0576/beaverhabits"; then
    msg_info "Stopping Service"
    systemctl stop beaverhabits
    msg_ok "Stopped Service"

    create_backup /opt/beaverhabits/.user

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "beaverhabits" "daya0576/beaverhabits" "tarball"

    msg_info "Syncing Dependencies"
    cd /opt/beaverhabits || exit
    $STD uv sync --no-dev
    msg_ok "Synced Dependencies"

    restore_backup

    msg_info "Starting Service"
    systemctl start beaverhabits
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
