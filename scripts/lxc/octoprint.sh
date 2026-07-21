#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2155,SC2046
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://octoprint.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="OctoPrint"
var_tags="${var_tags:-3d-printing}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-0}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git \
    libyaml-dev \
    build-essential
  msg_ok "Installed Dependencies"

  msg_info "Setup Python3"
  $STD apt install -y \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    python3-setuptools
  rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED
  msg_ok "Setup Python3"

  msg_info "Creating user octoprint"
  useradd -m -s /bin/bash -p "$(openssl passwd -1 octoprint)" octoprint
  usermod -aG sudo,tty,dialout octoprint
  chown -R octoprint:octoprint /opt
  echo "octoprint ALL=NOPASSWD: $(command -v systemctl) restart octoprint, $(command -v reboot), $(command -v poweroff)" > /etc/sudoers.d/octoprint
  msg_ok "Created user octoprint"

  msg_info "Installing OctoPrint"
  $STD sudo -u octoprint bash << EOF
mkdir /opt/octoprint
cd /opt/octoprint
python3 -m venv .
source bin/activate
pip install --upgrade pip
pip install wheel
pip install octoprint
EOF
  msg_ok "Installed OctoPrint"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/octoprint.service
[Unit]
Description=The snappy web interface for your 3D printer
After=network-online.target
Wants=network-online.target

[Service]
Environment="LC_ALL=C.UTF-8"
Environment="LANG=C.UTF-8"
Type=exec
User=octoprint
ExecStart=/opt/octoprint/bin/octoprint serve

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now octoprint
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:5000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/octoprint ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Stopping OctoPrint"
  systemctl stop octoprint
  msg_ok "Stopped OctoPrint"

  msg_info "Updating OctoPrint"
  source /opt/octoprint/bin/activate
  $STD pip3 install octoprint --upgrade
  msg_ok "Updated OctoPrint"

  msg_info "Starting OctoPrint"
  systemctl start octoprint
  msg_ok "Started OctoPrint"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
