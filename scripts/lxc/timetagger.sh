#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/almarklein/timetagger

# shellcheck disable=SC2034
APP="TimeTagger"
var_tags="${var_tags:-productivity;time-tracking}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git curl
  msg_ok "Installed Dependencies"

  PYTHON_VERSION="3.13" setup_uv

  msg_info "Installing TimeTagger"
  $STD uv pip install --system timetagger
  msg_ok "Installed TimeTagger"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/timetagger.service
[Unit]
Description=TimeTagger
After=network.target

[Service]
Type=simple
User=root
Environment=HOME=/root
ExecStart=/usr/local/bin/timetagger server --port 80
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now timetagger
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  render_header
  check_container_storage
  check_container_resources

  if [[ ! -f /usr/local/bin/timetagger ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  PYTHON_VERSION="3.13" setup_uv
  msg_info "Updating ${APP}"
  systemctl stop timetagger
  $STD uv pip install --system --upgrade timetagger
  systemctl start timetagger
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
