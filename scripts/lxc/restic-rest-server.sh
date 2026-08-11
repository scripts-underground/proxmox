#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/restic/rest-server

# shellcheck disable=SC2034
APP="Restic REST Server"
var_tags="${var_tags:-backup}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_git_repo="${var_lxc_git_repo:-restic/rest-server}"

function install_script() {
  local SYS_ARCH
  SYS_ARCH=$(get_system_arch)
  fetch_and_deploy_gh_release "rest-server" "$var_lxc_git_repo" "binary" "latest" "/opt/rest-server" "rest-server_*_linux_${SYS_ARCH}.tar.gz"
  chmod +x /opt/rest-server/rest-server
  mkdir -p /opt/rest-server/data

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/rest-server.service
[Unit]
Description=Restic REST Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/rest-server/rest-server --path /opt/rest-server/data --listen :80
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now rest-server
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}The REST API is available at:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
  echo -e "${INFO}${YW}Configure restic clients to use this endpoint as repository.${CL}"
}

function update_script() {
  render_header
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/rest-server/rest-server ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "rest-server" "$var_lxc_git_repo"; then
    systemctl stop rest-server
    local SYS_ARCH
    SYS_ARCH=$(get_system_arch)
    fetch_and_deploy_gh_release "rest-server" "$var_lxc_git_repo" "binary" "latest" "/opt/rest-server" "rest-server_*_linux_${SYS_ARCH}.tar.gz"
    chmod +x /opt/rest-server/rest-server
    systemctl start rest-server
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
