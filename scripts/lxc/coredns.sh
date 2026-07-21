#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://coredns.io/

# shellcheck disable=SC2034
APP="CoreDNS"
var_tags="${var_tags:-dns;network}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_gh_release "coredns" "coredns/coredns" "prebuild" "latest" "/usr/local/bin" "coredns_*_linux_$(get_system_arch).tgz"
  chmod +x /usr/local/bin/coredns
  mkdir -p /etc/coredns
  cat << 'EOF' > /etc/coredns/Corefile
. {
    forward . 1.1.1.1 1.0.0.1
    cache 30
    log
    errors
    health :8080
    ready :8181
}
EOF
  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/coredns.service
[Unit]
Description=CoreDNS DNS Server
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/coredns -conf /etc/coredns/Corefile
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now coredns
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} CoreDNS is listening on port 53 (DNS)${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}dns://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /usr/local/bin/coredns ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "coredns" "coredns/coredns"; then
    msg_info "Stopping Service"
    systemctl stop coredns
    msg_ok "Stopped Service"
    fetch_and_deploy_gh_release "coredns" "coredns/coredns" "prebuild" "latest" "/usr/local/bin" "coredns_*_linux_$(get_system_arch).tgz"
    chmod +x /usr/local/bin/coredns
    msg_info "Starting Service"
    systemctl start coredns
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
