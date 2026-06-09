#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
source <(curl -fsSL "$REPO_BASE/misc/build.func")

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Alex Indigo (alexindigo)
# License: MIT | https://github.com/alexindigo/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/pewdiepie-archdaemon/odysseus | https://pewdiepie-archdaemon.github.io/odysseus/

APP="Odysseus"
var_tags="${var_tags:-ai;workspace;llm}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/odysseus ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Checking for updates"
  cd /opt/odysseus
  $STD git fetch origin main
  LOCAL=$(git rev-parse HEAD)
  REMOTE=$(git rev-parse origin/main 2>/dev/null || echo "")
  if [[ "$LOCAL" != "$REMOTE" && -n "$REMOTE" ]]; then
    PYTHON_VERSION="3.12" setup_uv
    msg_info "Stopping Service"
    systemctl stop odysseus
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration"
    cp /opt/odysseus/.env /opt/odysseus.env.bak
    msg_ok "Backed up Configuration"

    $STD git pull origin main

    $STD uv pip install -r /opt/odysseus/requirements.txt --python=/opt/odysseus/venv/bin/python --upgrade

    msg_info "Restoring Configuration"
    cp /opt/odysseus.env.bak /opt/odysseus/.env
    rm -f /opt/odysseus.env.bak
    msg_ok "Restored Configuration"

    $STD /opt/odysseus/venv/bin/python /opt/odysseus/setup.py

    msg_info "Starting Service"
    systemctl start odysseus
    msg_ok "Started Service"
    msg_ok "Updated Successfully!"
  else
    msg_ok "${APP} is up to date"
  fi
  exit
}

function install_script() {
  color
  verb_ip6
  catch_errors
  setting_up_container
  network_check
  update_os

  msg_info "Installing Dependencies"
  $STD apt install -y \
    git \
    tmux
  msg_ok "Installed Dependencies"

  PYTHON_VERSION="3.12" setup_uv

  msg_info "Cloning Odysseus"
  $STD git clone https://github.com/pewdiepie-archdaemon/odysseus.git /opt/odysseus
  $STD git -C /opt/odysseus checkout main
  msg_ok "Cloned Odysseus"

  msg_info "Setting up Python Environment"
  cd /opt/odysseus
  $STD uv venv /opt/odysseus/venv
  $STD uv pip install -r /opt/odysseus/requirements.txt --python=/opt/odysseus/venv/bin/python
  msg_ok "Set up Python Environment"

  msg_info "Running Setup"
  cd /opt/odysseus
  ADMIN_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  export ODYSSEUS_ADMIN_USER="admin"
  export ODYSSEUS_ADMIN_PASSWORD="$ADMIN_PASS"
  /opt/odysseus/venv/bin/python /opt/odysseus/setup.py
  msg_ok "Setup Complete"
  echo -e "${INFO}${YW} Admin Username: admin${CL}"
  echo -e "${INFO}${YW} Admin Password: ${ADMIN_PASS}${CL}"

  msg_info "Creating Service"
  cat <<EOF >/etc/systemd/system/odysseus.service
[Unit]
Description=Odysseus AI Workspace
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/odysseus
Environment=PATH=/opt/odysseus/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/opt/odysseus/venv/bin/uvicorn app:app --host 0.0.0.0 --port 80
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now odysseus
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
}

source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
