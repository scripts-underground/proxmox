#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://pocketbase.io/ | Github: https://github.com/pocketbase/pocketbase

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Pocketbase"
var_tags="${var_tags:-database}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_gh_release "pocketbase" "pocketbase/pocketbase" "prebuild" "latest" "/opt/pocketbase" "pocketbase*linux_$(get_system_arch).zip"

  msg_info "Configuring Pocketbase"
  mkdir -p /opt/pocketbase/{pb_public,pb_migrations,pb_hooks}
  msg_ok "Configured Pocketbase"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/pocketbase.service
[Unit]
Description = pocketbase

[Service]
Type           = simple
LimitNOFILE    = 4096
Restart        = always
RestartSec     = 5s
StandardOutput = append:/opt/pocketbase/errors.log
StandardError  = append:/opt/pocketbase/errors.log
ExecStart      = /opt/pocketbase/pocketbase serve --http=0.0.0.0:8080

[Install]
WantedBy = multi-user.target
EOF
  systemctl enable -q --now pocketbase
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080/_/${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/systemd/system/pocketbase.service || ! -x /opt/pocketbase/pocketbase ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "pocketbase" "pocketbase/pocketbase"; then
    msg_info "Stopping Service"
    systemctl stop pocketbase
    msg_ok "Stopped Service"

    msg_info "Updating ${APP}"
    /opt/pocketbase/pocketbase update
    echo "${CHECK_UPDATE_RELEASE}" > ~/.pocketbase
    msg_ok "Updated ${APP}"

    msg_info "Starting Service"
    systemctl start pocketbase
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
