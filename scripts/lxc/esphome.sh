#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://esphome.io/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="ESPHome"
var_tags="${var_tags:-automation}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    libusb-1.0-0
  msg_ok "Installed Dependencies"

  VENV_PATH="/opt/esphome/.venv"
  PYTHON_VERSION="3.12" setup_uv

  msg_info "Installing ESPHome"
  mkdir -p /opt/esphome
  cd /opt/esphome || exit
  mkdir -p /root/config/
  $STD uv venv --clear "$VENV_PATH"
  $STD "$VENV_PATH/bin/python" -m ensurepip --upgrade
  $STD "$VENV_PATH/bin/python" -m pip install --upgrade pip
  $STD "$VENV_PATH/bin/python" -m pip install esphome esphome-device-builder esptool
  msg_ok "Installed ESPHome"

  msg_info "Linking esphome to /usr/local/bin"
  ln -sf "$VENV_PATH/bin/esphome" /usr/local/bin/esphome
  msg_ok "Linked esphome binary"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/esphome-device-builder.service
[Unit]
Description=ESPHome Device Builder
After=network.target

[Service]
ExecStart=${VENV_PATH}/bin/esphome-device-builder /root/config/
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now esphome-device-builder
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:6052${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/esphome-device-builder.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Installing Dependencies"
  $STD apt install -y libusb-1.0-0
  msg_ok "Installed Dependencies"

  msg_info "Stopping Service"
  systemctl stop esphome-device-builder 2> /dev/null || true
  msg_ok "Stopped Service"

  VENV_PATH="/opt/esphome/.venv"
  ESPHOME_BIN="${VENV_PATH}/bin/esphome"
  PYTHON_VERSION="3.12" setup_uv

  if [[ ! -d "$VENV_PATH" || ! -x "$ESPHOME_BIN" ]]; then
    msg_info "Migrating to uv/venv"
    rm -rf "$VENV_PATH"
    mkdir -p /opt/esphome
    cd /opt/esphome || exit
    $STD uv venv --clear "$VENV_PATH"
    $STD "$VENV_PATH/bin/python" -m ensurepip --upgrade
    $STD "$VENV_PATH/bin/python" -m pip install --upgrade pip
    $STD "$VENV_PATH/bin/python" -m pip install esphome esphome-device-builder esptool
    msg_ok "Migrated to uv/venv"
  else
    msg_info "Updating ESPHome Device Builder"
    $STD "$VENV_PATH/bin/python" -m pip install --upgrade esphome esphome-device-builder esptool
    msg_ok "Updated ESPHome Device Builder"
  fi

  msg_info "Linking esphome to /usr/local/bin"
  rm -f /usr/local/bin/esphome
  ln -s /opt/esphome/.venv/bin/esphome /usr/local/bin/esphome
  msg_ok "Linked esphome binary"

  msg_info "Starting Service"
  systemctl start esphome-device-builder
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
