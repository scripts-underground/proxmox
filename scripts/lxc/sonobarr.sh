#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: GoldenSpringness
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Dodelidoo-Labs/sonobarr

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="sonobarr"
var_tags="${var_tags:-music;discovery}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_gh_release "sonobarr" "Dodelidoo-Labs/sonobarr" "tarball"
  PYTHON_VERSION="3.12" setup_uv

  msg_info "Setting up sonobarr"
  $STD uv venv -c /opt/sonobarr/venv
  source /opt/sonobarr/venv/bin/activate
  $STD uv pip install --no-cache-dir -r /opt/sonobarr/requirements.txt
  mkdir -p /etc/sonobarr
  mv /opt/sonobarr/.sample-env /etc/sonobarr/.env
  sed -i "s/^secret_key=.*/secret_key=$(openssl rand -hex 16)/" /etc/sonobarr/.env
  sed -i "s/^sonobarr_superadmin_password=.*/sonobarr_superadmin_password=$(openssl rand -hex 16)/" /etc/sonobarr/.env
  echo "release_version=$(cat ~/.sonobarr)" >> /etc/sonobarr/.env
  echo "sonobarr_config_dir=/etc/sonobarr" >> /etc/sonobarr.env
  msg_ok "Set up sonobarr"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/sonobarr.service
[Unit]
Description=sonobarr Service
After=network.target

[Service]
WorkingDirectory=/opt/sonobarr/src
EnvironmentFile=/etc/sonobarr/.env
Environment="PATH=/opt/sonobarr/venv/bin"
ExecStart=/bin/bash -c 'gunicorn Sonobarr:app -c ../gunicorn_config.py'
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now sonobarr
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:5000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/sonobarr ]]; then
    msg_error "No sonobarr Installation Found!"
    exit
  fi

  PYTHON_VERSION="3.12" setup_uv

  if check_for_gh_release "sonobarr" "Dodelidoo-Labs/sonobarr"; then
    msg_info "Stopping Service"
    systemctl stop sonobarr
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "sonobarr" "Dodelidoo-Labs/sonobarr" "tarball"

    msg_info "Updating sonobarr"
    $STD uv venv -c /opt/sonobarr/venv
    $STD source /opt/sonobarr/venv/bin/activate
    $STD uv pip install --no-cache-dir -r /opt/sonobarr/requirements.txt
    sed -i "/release_version/s/=.*/=$(cat ~/.sonobarr)/" /etc/sonobarr/.env
    msg_ok "Updated sonobarr"

    msg_info "Starting Service"
    systemctl start sonobarr
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
