#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: finkerle
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/raydak-labs/configarr

# shellcheck disable=SC2034
APP="Configarr"
var_tags="${var_tags:-arr}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git
  msg_ok "Installed Dependencies"
  fetch_and_deploy_gh_release "configarr" "raydak-labs/configarr" "prebuild" "latest" "/opt/configarr" "configarr-linux-$(get_system_arch).tar.xz"
  cat << 'EOF' > /opt/configarr/.env
ROOT_PATH=/opt/configarr
CUSTOM_REPO_ROOT=/opt/configarr/custom
CONFIG_LOCATION=/opt/configarr/config.yml
SECRETS_LOCATION=/opt/configarr/secrets.yml
EOF
  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/configarr-task.service
[Unit]
Description=Configarr
[Service]
Type=simple
WorkingDirectory=/opt/configarr
ExecStart=/opt/configarr/configarr
EOF
  cat << 'EOF' > /etc/systemd/system/configarr-task.timer
[Unit]
Description=Configarr Timer
[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
[Install]
WantedBy=timers.target
EOF
  systemctl enable -q --now configarr-task.timer
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8989${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/configarr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "configarr" "raydak-labs/configarr"; then
    msg_info "Stopping Timer"
    systemctl stop configarr-task.timer
    msg_ok "Stopped Timer"
    create_backup /opt/configarr/config.yml /opt/configarr/secrets.yml /opt/configarr/.env
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "configarr" "raydak-labs/configarr" "prebuild" "latest" "/opt/configarr" "configarr-linux-$(get_system_arch).tar.xz"
    restore_backup
    msg_info "Starting Timer"
    systemctl start configarr-task.timer
    msg_ok "Started Timer"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
