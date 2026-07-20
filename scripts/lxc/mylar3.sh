#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: davalanche
# Co-Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/mylar3/mylar3

APP="Mylar3"
var_tags="${var_tags:-torrent;downloader;comic}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  cat << EOF > /etc/apt/sources.list.d/non-free.sources
Types: deb
URIs: http://deb.debian.org/debian
Suites: bookworm
Components: non-free non-free-firmware
EOF
  $STD apt update
  $STD apt install -y unrar
  msg_ok "Installed Dependencies"

  PYTHON_VERSION="3.11" setup_uv
  fetch_and_deploy_gh_release "mylar3" "MylarComics/mylar3" "tarball"

  msg_info "Installing Mylar3"
  mkdir -p /opt/mylar3-data
  $STD uv venv --clear /opt/mylar3/.venv
  $STD /opt/mylar3/.venv/bin/python -m ensurepip --upgrade
  $STD /opt/mylar3/.venv/bin/python -m pip install --upgrade pip
  $STD /opt/mylar3/.venv/bin/python -m pip install --no-cache-dir -r /opt/mylar3/requirements.txt
  msg_ok "Installed Mylar3"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/mylar3.service
[Unit]
Description=Mylar3 Service
After=network-online.target

[Service]
ExecStart=/opt/mylar3/.venv/bin/python /opt/mylar3/Mylar.py --daemon --nolaunch --datadir=/opt/mylar3-data
GuessMainPID=no
Type=forking
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now mylar3
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8090${CL}"
}

function update_script() {
  header_info
  if [[ ! -d /opt/mylar3 ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "mylar3" "MylarComics/mylar3"; then
    msg_info "Stopping Service"
    systemctl stop mylar3
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "mylar3" "MylarComics/mylar3" "tarball"

    msg_info "Updating Python Dependencies"
    $STD uv venv --clear /opt/mylar3/.venv
    $STD /opt/mylar3/.venv/bin/python -m ensurepip --upgrade
    $STD /opt/mylar3/.venv/bin/python -m pip install --upgrade pip
    $STD /opt/mylar3/.venv/bin/python -m pip install --no-cache-dir -r /opt/mylar3/requirements.txt
    msg_ok "Updated Python Dependencies"

    msg_info "Starting Service"
    systemctl start mylar3
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
