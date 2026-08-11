#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/AnalogJ/scrutiny

# shellcheck disable=SC2034
APP="Scrutiny"
var_tags="${var_tags:-monitoring;smart}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_git_repo="${var_lxc_git_repo:-AnalogJ/scrutiny}"

function install_script() {
  msg_info "Installing Scrutiny"
  local SYS_ARCH
  SYS_ARCH=$(get_system_arch)
  fetch_and_deploy_gh_release "scrutiny-web" "$var_lxc_git_repo" "binary" "latest" "/opt/scrutiny" "scrutiny-web-linux-${SYS_ARCH}"
  chmod +x "/opt/scrutiny/scrutiny-web-linux-${SYS_ARCH}"
  ln -sf "/opt/scrutiny/scrutiny-web-linux-${SYS_ARCH}" /opt/scrutiny/scrutiny-web
  msg_ok "Installed Scrutiny"

  msg_info "Configuring Scrutiny"
  mkdir -p /opt/scrutiny/config
  cat << EOF > /opt/scrutiny/config/scrutiny.yaml
version: 1
web:
  listen:
    port: 80
    host: 0.0.0.0
  database:
    location: /opt/scrutiny/config/scrutiny.db
EOF
  msg_ok "Configured Scrutiny"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/scrutiny.service
[Unit]
Description=Scrutiny Web UI
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/scrutiny/scrutiny-web start --config /opt/scrutiny/config/scrutiny.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now scrutiny
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
  echo -e "${INFO}${YW}SMART data collection requires the scrutiny-collector addon — install it on your PVE host.${CL}"
}

function update_script() {
  render_header
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/scrutiny ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "scrutiny-web" "$var_lxc_git_repo"; then
    msg_info "Updating ${APP}"
    systemctl stop scrutiny
    local SYS_ARCH
    SYS_ARCH=$(get_system_arch)
    fetch_and_deploy_gh_release "scrutiny-web" "$var_lxc_git_repo" "binary" "latest" "/opt/scrutiny" "scrutiny-web-linux-${SYS_ARCH}"
    chmod +x "/opt/scrutiny/scrutiny-web-linux-${SYS_ARCH}"
    ln -sf "/opt/scrutiny/scrutiny-web-linux-${SYS_ARCH}" /opt/scrutiny/scrutiny-web
    systemctl start scrutiny
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
