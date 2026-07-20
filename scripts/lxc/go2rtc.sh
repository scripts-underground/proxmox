#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/AlexxIT/go2rtc

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="go2rtc"
var_tags="${var_tags:-streaming;video}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y ffmpeg
  msg_ok "Installed Dependencies"

  USE_ORIGINAL_FILENAME="true" fetch_and_deploy_gh_release "go2rtc" "AlexxIT/go2rtc" "singlefile" "latest" "/opt/go2rtc" "go2rtc_linux_$(get_system_arch)"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/go2rtc.service
[Unit]
Description=go2rtc service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/go2rtc
ExecStart=/opt/go2rtc/go2rtc_linux_$(get_system_arch)

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now go2rtc
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:1984${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/go2rtc ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "go2rtc" "AlexxIT/go2rtc"; then
    msg_info "Stopping Service"
    systemctl stop go2rtc
    msg_ok "Stopped Service"

    USE_ORIGINAL_FILENAME="true" fetch_and_deploy_gh_release "go2rtc" "AlexxIT/go2rtc" "singlefile" "latest" "/opt/go2rtc" "go2rtc_linux_$(get_system_arch)"

    msg_info "Starting Service"
    systemctl start go2rtc
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
