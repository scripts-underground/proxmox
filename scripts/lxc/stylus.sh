#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: luismco
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/mmastrac/stylus

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Stylus"
var_tags="${var_tags:-network}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_fuse="${var_fuse:-yes}"

function install_script() {
  fetch_and_deploy_gh_release "stylus" "mmastrac/stylus" "singlefile" "latest" "/usr/bin/" "*_linux_$(get_system_arch)"

  msg_info "Configuring Stylus"
  $STD stylus init /opt/stylus/
  msg_ok "Configured Stylus"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/stylus.service
[Unit]
Description=Stylus Service
After=network.target

[Service]
Type=simple
ExecStart=stylus run /opt/stylus/
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now stylus
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/stylus ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "stylus" "mmastrac/stylus"; then
    msg_info "Stopping Service"
    systemctl stop stylus
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "stylus" "mmastrac/stylus" "singlefile" "latest" "/usr/bin/" "*_linux_$(get_system_arch)"

    msg_info "Starting Service"
    systemctl start stylus
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
