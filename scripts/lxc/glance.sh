#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: kristocopani
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/glanceapp/glance
# shellcheck disable=SC2034
APP="Glance"
var_tags="${var_tags:-dashboard}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
function install_script() {
  fetch_and_deploy_gh_release "glance" "glanceapp/glance" "prebuild" "latest" "/opt/glance" "glance-linux-$(get_system_arch).tar.gz"
  msg_info "Configuring Glance"
  mkdir -p /opt/glance_data
  cat << 'EOF' > /opt/glance_data/glance.yml
pages:
  - name: Start
    columns:
      - size: full
        widgets:
          - type: search
            autofocus: true
          - type: bookmarks
            groups:
              - title: General
                links:
                  - title: Google
                    url: https://www.google.com/
EOF
  msg_ok "Configured Glance"
  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/glance.service
[Unit]
Description=Glance Daemon
After=network.target
[Service]
Type=simple
WorkingDirectory=/opt/glance
ExecStart=/opt/glance/glance --config /opt/glance_data/glance.yml
TimeoutStopSec=20
KillMode=process
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now glance
  msg_ok "Created Service"
}
function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
}
function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/glance ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "glance" "glanceapp/glance"; then
    msg_info "Stopping Service"
    systemctl stop glance
    msg_ok "Stopped Service"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "glance" "glanceapp/glance" "prebuild" "latest" "/opt/glance" "glance-linux-$(get_system_arch).tar.gz"
    msg_info "Starting Service"
    systemctl start glance
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
