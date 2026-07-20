#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/bastienwirtz/homer

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Homer"
var_tags="${var_tags:-dashboard}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_gh_release "homer" "bastienwirtz/homer" "prebuild" "latest" "/opt/homer" "homer.zip"

  msg_info "Configuring Homer"
  cp /opt/homer/assets/config.yml.dist /opt/homer/assets/config.yml
  msg_ok "Configured Homer"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/homer.service
[Unit]
Description=Homer Dashboard
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/homer
ExecStart=python3 -m http.server 8010

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now homer
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8010${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/homer ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "homer" "bastienwirtz/homer"; then
    msg_info "Stopping Service"
    systemctl stop homer
    msg_ok "Stopped Service"

    msg_info "Backing up assets directory"
    cd ~ || exit
    mkdir -p assets-backup
    cp -R /opt/homer/assets/. assets-backup
    msg_ok "Backed up assets directory"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "homer" "bastienwirtz/homer" "prebuild" "latest" "/opt/homer" "homer.zip"

    msg_info "Restoring assets directory"
    cd ~ || exit
    cp -Rf assets-backup/. /opt/homer/assets/
    rm -rf assets-backup
    msg_ok "Restored assets directory"

    msg_info "Starting Service"
    systemctl start homer
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
