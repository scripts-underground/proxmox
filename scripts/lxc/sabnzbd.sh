#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster) | Co-Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://sabnzbd.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="SABnzbd"
var_tags="${var_tags:-downloader}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    par2 \
    p7zip-full
  msg_ok "Installed Dependencies"

  PYTHON_VERSION="3.13" setup_uv

  msg_info "Setup Unrar"
  cat << EOF > /etc/apt/sources.list.d/non-free.sources
Types: deb
URIs: http://deb.debian.org/debian/
Suites: trixie
Components: non-free
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
  $STD apt update
  $STD apt install -y unrar
  msg_ok "Setup Unrar"

  fetch_and_deploy_gh_release "sabnzbd-org" "sabnzbd/sabnzbd" "prebuild" "latest" "/opt/sabnzbd" "SABnzbd-*-src.tar.gz"

  msg_info "Installing SABnzbd"
  $STD uv venv --clear /opt/sabnzbd/venv
  $STD uv pip install -r /opt/sabnzbd/requirements.txt --python=/opt/sabnzbd/venv/bin/python
  msg_ok "Installed SABnzbd"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/sabnzbd.service
[Unit]
Description=SABnzbd
After=network.target

[Service]
WorkingDirectory=/opt/sabnzbd
ExecStart=/opt/sabnzbd/venv/bin/python SABnzbd.py -s 0.0.0.0:7777
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now sabnzbd
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:7777${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if par2 --version | grep -q "par2cmdline-turbo"; then
    fetch_and_deploy_gh_release "par2cmdline-turbo" "animetosho/par2cmdline-turbo" "prebuild" "latest" "/usr/bin/" "*-linux-$(get_system_arch).zip"
  fi

  if [[ ! -d /opt/sabnzbd ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "sabnzbd-org" "sabnzbd/sabnzbd"; then
    PYTHON_VERSION="3.13" setup_uv
    systemctl stop sabnzbd
    cp -r /opt/sabnzbd "/opt/sabnzbd_backup_$(date +%s)"
    fetch_and_deploy_gh_release "sabnzbd-org" "sabnzbd/sabnzbd" "prebuild" "latest" "/opt/sabnzbd" "SABnzbd-*-src.tar.gz"

    if [[ ! -d /opt/sabnzbd/venv ]]; then
      msg_info "Migrating SABnzbd to uv virtual environment"
      $STD uv venv --clear /opt/sabnzbd/venv
      msg_ok "Created uv venv at /opt/sabnzbd/venv"
    fi

    if [[ -f /etc/systemd/system/sabnzbd.service ]] && grep -q "ExecStart=python3 SABnzbd.py" /etc/systemd/system/sabnzbd.service; then
      sed -i "s|ExecStart=python3 SABnzbd.py|ExecStart=/opt/sabnzbd/venv/bin/python SABnzbd.py|" /etc/systemd/system/sabnzbd.service
      systemctl daemon-reload
      msg_ok "Updated SABnzbd service to use uv venv"
    fi
    $STD uv pip install --upgrade pip --python=/opt/sabnzbd/venv/bin/python
    $STD uv pip install -r /opt/sabnzbd/requirements.txt --python=/opt/sabnzbd/venv/bin/python

    systemctl start sabnzbd
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
