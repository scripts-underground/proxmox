#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://release-argus.io/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Argus"
var_tags="${var_tags:-watcher}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-3}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_gh_release "Argus" "release-argus/Argus" "singlefile" "latest" "/opt/argus" "Argus*linux-$(get_system_arch)"

  msg_info "Setup Argus Config"
  cat << EOF > /opt/argus/config.yml
settings:
  log:
    level: INFO
    timestamps: false
  data:
    database_file: data/argus.db
  web:
    listen_host: 0.0.0.0
    listen_port: 8080
    route_prefix: /

defaults:
  service:
    options:
      interval: 30m
      semantic_versioning: true
    latest_version:
      allow_invalid_certs: false
      use_prerelease: false
    dashboard:
      auto_approve: true
  webhook:
    desired_status_code: 201

service:
  release-argus/argus:
    latest_version:
      type: github
      url: release-argus/argus
    dashboard:
      icon: https://raw.githubusercontent.com/release-argus/Argus/master/web/ui/react-app/public/favicon.svg
      icon_link_to: https://release-argus.io
      web_url: https://github.com/release-argus/Argus/blob/master/CHANGELOG.md

  community-scripts/ProxmoxVE:
    latest_version:
      type: github
      url: community-scripts/ProxmoxVE
      use_prerelease: false
    dashboard:
      icon: https://raw.githubusercontent.com/community-scripts/ProxmoxVE/refs/heads/main/misc/images/logo.png
      icon_link_to: https://community-scripts.org/
      web_url: https://github.com/community-scripts/ProxmoxVE/releases
EOF
  msg_ok "Setup Config"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/argus.service
[Unit]
Description=Argus
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/argus
ExecStart=/opt/argus/Argus
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now argus
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

  if [[ ! -d /opt/argus ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "argus" "release-argus/Argus"; then
    msg_info "Stopping Service"
    systemctl stop argus
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "Argus" "release-argus/Argus" "singlefile" "latest" "/opt/argus" "Argus*linux-$(get_system_arch)"

    msg_info "Starting Service"
    systemctl start argus
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
