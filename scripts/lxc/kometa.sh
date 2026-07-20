#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Kometa-Team/Kometa

# shellcheck disable=SC2034
APP="Kometa"
var_tags="${var_tags:-media;streaming}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git build-essential
  msg_ok "Installed Dependencies"

  PYTHON_VERSION="3.13" setup_uv

  msg_info "Installing Kometa"
  fetch_and_deploy_gh_release "kometa" "Kometa-Team/Kometa" "tarball"
  cd /opt/kometa || exit
  $STD uv venv /opt/kometa/.venv
  $STD uv pip install -r requirements.txt -p /opt/kometa/.venv/bin/python
  mkdir -p config/assets
  msg_ok "Installed Kometa"

  msg_info "Installing Kometa Quickstart"
  fetch_and_deploy_gh_release "kometa-quickstart" "Kometa-Team/Quickstart" "tarball"
  cd /opt/kometa-quickstart || exit
  $STD uv venv /opt/kometa-quickstart/.venv
  $STD uv pip install -r requirements.txt -p /opt/kometa-quickstart/.venv/bin/python
  mkdir -p config
  msg_ok "Installed Kometa Quickstart"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/kometa.service
[Unit]
Description=Kometa Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/kometa
ExecStart=/opt/kometa/.venv/bin/python /opt/kometa/kometa.py --config /opt/kometa/config/config.yml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/kometa-quickstart.service
[Unit]
Description=Kometa Quickstart Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/kometa-quickstart
ExecStart=/opt/kometa-quickstart/.venv/bin/python /opt/kometa-quickstart/quickstart.py
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now kometa-quickstart
  msg_ok "Created Services"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access Kometa Quickstart:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:7171${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/kometa ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "kometa" "Kometa-Team/Kometa"; then
    msg_info "Stopping Kometa Service"
    systemctl stop kometa
    [[ -d /opt/kometa-quickstart ]] && systemctl stop kometa-quickstart
    msg_ok "Stopped Kometa Service"

    msg_info "Backing up config"
    cp /opt/kometa/config/config.yml /opt
    msg_ok "Backed up config"

    PYTHON_VERSION="3.13" setup_uv
    fetch_and_deploy_gh_release "kometa" "Kometa-Team/Kometa" "tarball"

    msg_info "Updating Kometa"
    cd /opt/kometa || exit
    [[ -d /opt/kometa/.venv ]] || $STD uv venv /opt/kometa/.venv
    $STD uv pip install -r requirements.txt -p /opt/kometa/.venv/bin/python
    mkdir -p config/assets
    cp /opt/config.yml config/config.yml
    msg_ok "Updated Kometa"

    msg_info "Starting Kometa Service"
    systemctl start kometa
    msg_ok "Started Kometa Service"
  fi

  if [[ -d /opt/kometa-quickstart ]] && check_for_gh_release "kometa-quickstart" "Kometa-Team/Quickstart"; then
    msg_info "Updating Kometa Quickstart"
    systemctl stop kometa-quickstart
    fetch_and_deploy_gh_release "kometa-quickstart" "Kometa-Team/Quickstart" "tarball"
    cd /opt/kometa-quickstart || exit
    $STD uv pip install -r requirements.txt -p /opt/kometa-quickstart/.venv/bin/python
    systemctl start kometa-quickstart
    msg_ok "Updated Kometa Quickstart"
  fi

  msg_ok "Updated Successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
