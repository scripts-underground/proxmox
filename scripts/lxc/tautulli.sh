#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://tautulli.com/

# shellcheck disable=SC2034
APP="Tautulli"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git
  msg_ok "Installed Dependencies"

  PYTHON_VERSION="3.13" setup_uv
  fetch_and_deploy_gh_release "Tautulli" "Tautulli/Tautulli" "tarball"

  msg_info "Installing Tautulli"
  cd /opt/Tautulli || exit
  TAUTULLI_VERSION=$(get_latest_github_release "Tautulli/Tautulli" "false")
  echo "${TAUTULLI_VERSION}" > /opt/Tautulli/version.txt
  echo "master" > /opt/Tautulli/branch.txt
  $STD uv venv --clear
  $STD source /opt/Tautulli/.venv/bin/activate
  $STD uv pip install -r requirements.txt
  $STD uv pip install pyopenssl
  $STD uv pip install "setuptools<81"
  msg_ok "Installed Tautulli"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/tautulli.service
[Unit]
Description=Tautulli
After=syslog.target network.target

[Service]
WorkingDirectory=/opt/Tautulli/
Restart=on-failure
RestartSec=5
Type=simple
ExecStart=/opt/Tautulli/.venv/bin/python3 /opt/Tautulli/Tautulli.py
KillSignal=SIGINT
TimeoutStopSec=20
SyslogIdentifier=tautulli

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now tautulli
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8181${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/Tautulli/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "Tautulli" "Tautulli/Tautulli"; then
    PYTHON_VERSION="3.13" setup_uv

    msg_info "Stopping Service"
    systemctl stop tautulli
    msg_ok "Stopped Service"

    msg_info "Backing up config and database"
    cp /opt/Tautulli/config.ini /opt/tautulli_config.ini.backup
    cp /opt/Tautulli/tautulli.db /opt/tautulli.db.backup
    msg_ok "Backed up config and database"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "Tautulli" "Tautulli/Tautulli" "tarball"

    msg_info "Updating Tautulli"
    cd /opt/Tautulli || exit
    TAUTULLI_VERSION=$(get_latest_github_release "Tautulli/Tautulli" "false")
    echo "${TAUTULLI_VERSION}" > /opt/Tautulli/version.txt
    echo "master" > /opt/Tautulli/branch.txt
    $STD uv venv -c
    $STD source /opt/Tautulli/.venv/bin/activate
    $STD uv pip install -r requirements.txt
    $STD uv pip install pyopenssl
    $STD uv pip install "setuptools<81"
    msg_ok "Updated Tautulli"

    msg_info "Restoring config and database"
    cp /opt/tautulli_config.ini.backup /opt/Tautulli/config.ini
    cp /opt/tautulli.db.backup /opt/Tautulli/tautulli.db
    rm -f /opt/{tautulli_config.ini.backup,tautulli.db.backup}
    msg_ok "Restored config and database"

    msg_info "Starting Service"
    systemctl start tautulli
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
