#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.hyperhdr.eu/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="HyperHDR"
var_tags="${var_tags:-ambient-lightning}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-0}"
var_gpu="${var_gpu:-yes}"

function install_script() {
  msg_info "Setting up HyperHDR repository"
  setup_deb822_repo \
    "hyperhdr" \
    "https://awawa-dev.github.io/hyperhdr.public.apt.gpg.key" \
    "https://awawa-dev.github.io" \
    "$(get_os_info codename)"
  msg_ok "Set up HyperHDR repository"

  msg_info "Installing HyperHDR"
  $STD apt install -y hyperhdr
  msg_ok "Installed HyperHDR"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/hyperhdr.service
[Unit]
Description=HyperHDR Service
After=syslog.target network.target

[Service]
Restart=on-failure
RestartSec=5
Type=simple
ExecStart=/usr/bin/hyperhdr

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now hyperhdr
  msg_ok "Created Service"

  setup_hwaccel
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8090${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /usr/bin/hyperhdr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP} LXC"
  $STD apt update
  $STD apt install -y hyperhdr
  msg_ok "Updated ${APP} LXC"
  msg_ok "Updated successfully!"
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
