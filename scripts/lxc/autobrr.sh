#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://autobrr.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Autobrr"
var_tags="${var_tags:-arr}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  ARCH=$(uname -m)
  [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"

  fetch_and_deploy_gh_release "autobrr" "autobrr/autobrr" "prebuild" "latest" "/usr/local/bin" "autobrr_*_linux_${ARCH}.tar.gz"

  msg_info "Configuring Autobrr"
  mkdir -p /root/.config/autobrr
  cat << EOF > /root/.config/autobrr/config.toml
host = "0.0.0.0"
port = 7474
logLevel = "DEBUG"
sessionSecret = "$(openssl rand -base64 24)"
EOF
  msg_ok "Configured Autobrr"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/autobrr.service
[Unit]
Description=autobrr service
After=syslog.target network-online.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/local/bin/autobrr --config=/root/.config/autobrr/

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable --now -q autobrr
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:7474${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /root/.config/autobrr/config.toml ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "autobrr" "autobrr/autobrr"; then
    msg_info "Stopping Service"
    systemctl stop autobrr
    msg_ok "Stopped Service"

    ARCH=$(uname -m)
    [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
    fetch_and_deploy_gh_release "autobrr" "autobrr/autobrr" "prebuild" "latest" "/usr/local/bin" "autobrr_*_linux_${ARCH}.tar.gz"

    msg_info "Starting Service"
    systemctl start autobrr
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
