#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster) | Co-Author: MountyMapleSyrup (MountyMapleSyrup)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://gitlab.com/LazyLibrarian/LazyLibrarian

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="LazyLibrarian"
var_tags="${var_tags:-eBook}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    git \
    libpng-dev \
    libjpeg-dev \
    libtiff-dev \
    imagemagick
  msg_ok "Installed Dependencies"

  PYTHON_VERSION="3.12" setup_uv

  msg_info "Installing LazyLibrarian"
  $STD git clone https://gitlab.com/LazyLibrarian/LazyLibrarian /opt/LazyLibrarian
  $STD uv venv --clear /opt/LazyLibrarian/venv --python 3.12
  cd /opt/LazyLibrarian || exit
  $STD uv pip install .
  msg_ok "Installed LazyLibrarian"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/lazylibrarian.service
[Unit]
Description=LazyLibrarian Daemon
After=syslog.target network.target

[Service]
UMask=0002
Type=simple
ExecStart=/opt/LazyLibrarian/venv/bin/python3 /opt/LazyLibrarian/LazyLibrarian.py
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now lazylibrarian
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5299${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/LazyLibrarian/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping LazyLibrarian"
  systemctl stop lazylibrarian
  msg_ok "Stopped LazyLibrarian"

  PYTHON_VERSION="3.12" setup_uv

  msg_info "Updating LazyLibrarian"
  $STD git -C /opt/LazyLibrarian pull origin master
  cd /opt/LazyLibrarian || exit
  $STD uv pip install . --python /opt/LazyLibrarian/venv/bin/python3
  msg_ok "Updated LazyLibrarian"

  msg_info "Starting LazyLibrarian"
  systemctl start lazylibrarian
  msg_ok "Started LazyLibrarian"

  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
