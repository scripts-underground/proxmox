#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: JasonGreenC
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/thecfu/scraparr

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Scraparr"
var_tags="${var_tags:-arr;monitoring}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  PYTHON_VERSION="3.13" setup_uv
  fetch_and_deploy_gh_release "scrappar" "thecfu/scraparr" "tarball" "latest" "/opt/scraparr"

  msg_info "Installing Scraparr"
  $STD uv venv --clear /opt/scraparr/.venv
  $STD /opt/scraparr/.venv/bin/python -m ensurepip --upgrade
  $STD /opt/scraparr/.venv/bin/python -m pip install --upgrade pip
  $STD /opt/scraparr/.venv/bin/python -m pip install -r /opt/scraparr/src/scraparr/requirements.txt
  chmod -R 755 /opt/scraparr
  mkdir -p /scraparr/config
  mv /opt/scraparr/config.yaml /scraparr/config/config.yaml 2> /dev/null || true
  chmod -R 755 /scraparr
  msg_ok "Installed Scraparr"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/scraparr.service
[Unit]
Description=Scraparr
Wants=network-online.target
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/scraparr/src
ExecStart=/opt/scraparr/.venv/bin/python -m scraparr.scraparr
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now scraparr
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:7100${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/scraparr/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "scraparr" "thecfu/scraparr"; then
    msg_info "Stopping Service"
    systemctl stop scraparr
    msg_ok "Stopped Service"

    PYTHON_VERSION="3.12" setup_uv
    fetch_and_deploy_gh_release "scrappar" "thecfu/scraparr" "tarball" "latest" "/opt/scraparr"

    msg_info "Updating Scraparr"
    $STD uv venv --clear /opt/scraparr/.venv
    $STD /opt/scraparr/.venv/bin/python -m ensurepip --upgrade
    $STD /opt/scraparr/.venv/bin/python -m pip install --upgrade pip
    $STD /opt/scraparr/.venv/bin/python -m pip install -r /opt/scraparr/src/scraparr/requirements.txt
    chmod -R 755 /opt/scraparr
    msg_ok "Updated Scraparr"

    msg_info "Starting Service"
    systemctl start scraparr
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
