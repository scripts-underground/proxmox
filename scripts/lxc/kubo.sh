#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://ipfs.tech/
# shellcheck disable=SC2034
APP="Kubo"
var_tags="${var_tags:-sharing}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
function install_script() {
  fetch_and_deploy_gh_release "kubo" "ipfs/kubo" "prebuild" "latest" "/usr/local/kubo" "kubo*linux-$(get_system_arch).tar.gz"
  cd /usr/local/kubo || exit
  $STD bash install.sh
  msg_info "Configuring IPFS"
  ipfs init
  ipfs config --json API.HTTPHeaders.Access-Control-Allow-Origin '["*"]'
  ipfs config --json API.HTTPHeaders.Access-Control-Allow-Methods '["PUT", "POST"]'
  msg_ok "Configured IPFS"
  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/ipfs.service
[Unit]
Description=IPFS Daemon
After=syslog.target network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/ipfs daemon
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now ipfs
  msg_ok "Created Service"
}
function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5001${CL}"
}
function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /usr/local/bin/ipfs ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "kubo" "ipfs/kubo"; then
    msg_info "Stopping Service"
    systemctl stop ipfs
    msg_ok "Stopped Service"
    rm -rf /usr/local/kubo
    fetch_and_deploy_gh_release "kubo" "ipfs/kubo" "prebuild" "latest" "/usr/local/kubo" "kubo*linux-$(get_system_arch).tar.gz"
    cd /usr/local/kubo || exit
    $STD bash install.sh
    msg_info "Starting Service"
    systemctl start ipfs
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
