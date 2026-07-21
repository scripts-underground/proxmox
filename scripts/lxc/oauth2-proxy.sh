#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: bvdberg01
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/oauth2-proxy/oauth2-proxy/

APP="OAuth2-Proxy"
var_tags="${var_tags:-authentication;proxy}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-3}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

  fetch_and_deploy_gh_release "oauth2-proxy" "oauth2-proxy/oauth2-proxy" "prebuild" "latest" "/opt/oauth2-proxy" "oauth2-proxy*linux-${ARCH}.tar.gz"
  touch /opt/oauth2-proxy/config.toml

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/oauth2-proxy.service
[Unit]
Description=OAuth2-Proxy Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/oauth2-proxy
ExecStart=/opt/oauth2-proxy/oauth2-proxy --config config.toml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now oauth2-proxy
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Now you can modify /opt/oauth2-proxy/config.toml with your needed config.${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/oauth2-proxy ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

  if check_for_gh_release "oauth2-proxy" "oauth2-proxy/oauth2-proxy"; then
    msg_info "Stopping Service"
    systemctl stop oauth2-proxy
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "oauth2-proxy" "oauth2-proxy/oauth2-proxy" "prebuild" "latest" "/opt/oauth2-proxy" "oauth2-proxy*linux-${ARCH}.tar.gz"

    msg_info "Starting Service"
    systemctl start oauth2-proxy
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
