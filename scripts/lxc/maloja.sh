#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/krateng/maloja

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Maloja"
var_tags="${var_tags:-music;scrobbler}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_git_repo="${var_lxc_git_repo:-krateng/maloja}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git curl
  msg_ok "Installed Dependencies"

  PYTHON_VERSION="3.13" setup_uv

  msg_info "Installing Maloja"
  $STD uv pip install --system malojaserver
  msg_ok "Installed Maloja"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/maloja.service
[Unit]
Description=Maloja Scrobbler
After=network.target

[Service]
Type=simple
User=root
Environment=HOME=/root
ExecStart=/usr/local/bin/maloja run --port 80
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now maloja
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
  echo -e "${INFO}${YW}Maloja serves scrobble stats at the root and accepts Audioscrobbler-compatible scrobbles at /apis/audioscrobbler.${CL}"
}

function update_script() {
  render_header
  check_container_storage
  check_container_resources

  if [[ ! -f /usr/local/bin/maloja ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  PYTHON_VERSION="3.13" setup_uv
  msg_info "Updating ${APP}"
  systemctl stop maloja
  $STD uv pip install --system --upgrade malojaserver
  systemctl start maloja
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
