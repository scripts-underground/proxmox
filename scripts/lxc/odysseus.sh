#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/pewdiepie-archdaemon/odysseus | https://pewdiepie-archdaemon.github.io/odysseus/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Odysseus"
var_tags="${var_tags:-ai;workspace;llm}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"
var_pinned_commit="${var_pinned_commit:-}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    git \
    tmux
  msg_ok "Installed Dependencies"

  PYTHON_VERSION="3.12" setup_uv

  msg_info "Cloning Odysseus"
  $STD git clone https://github.com/pewdiepie-archdaemon/odysseus.git /opt/odysseus
  if [[ -n "$var_pinned_commit" ]]; then
    $STD git -C /opt/odysseus checkout "$var_pinned_commit"
  fi
  msg_ok "Cloned Odysseus"

  msg_info "Setting up Python Environment"
  cd /opt/odysseus || exit
  $STD uv venv /opt/odysseus/venv
  $STD uv pip install -r /opt/odysseus/requirements.txt --python=/opt/odysseus/venv/bin/python
  msg_ok "Set up Python Environment"

  msg_info "Running Setup"
  cd /opt/odysseus || exit
  ADMIN_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  export ODYSSEUS_ADMIN_USER="admin"
  export ODYSSEUS_ADMIN_PASSWORD="$ADMIN_PASS"
  /opt/odysseus/venv/bin/python /opt/odysseus/setup.py
  msg_ok "Setup Complete"
  echo -e "${INFO}${YW} Admin Username: admin${CL}"
  echo -e "${INFO}${YW} Admin Password: ${ADMIN_PASS}${CL}"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/odysseus.service
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

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/odysseus ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Checking for updates"
  cd /opt/odysseus || exit
  $STD git fetch origin
  if [[ -n "$var_pinned_commit" ]]; then
    LOCAL=$(git rev-parse HEAD)
    if [[ "$LOCAL" != "$var_pinned_commit" ]]; then
      PYTHON_VERSION="3.12" setup_uv
      msg_info "Stopping Service"
      systemctl stop odysseus
      msg_ok "Stopped Service"
      msg_info "Switching to pinned commit"
      $STD git -C /opt/odysseus checkout "$var_pinned_commit"
      msg_ok "Switched to pinned commit"
      $STD uv pip install -r /opt/odysseus/requirements.txt --python=/opt/odysseus/venv/bin/python --upgrade
      $STD /opt/odysseus/venv/bin/python /opt/odysseus/setup.py
      msg_info "Starting Service"
      systemctl start odysseus
      msg_ok "Started Service"
      msg_ok "Updated Successfully!"
    else
      msg_ok "${APP} is at the pinned commit — no update needed"
    fi
  else
    $STD git pull origin main
    PYTHON_VERSION="3.12" setup_uv
    msg_info "Stopping Service"
    systemctl stop odysseus
    msg_ok "Stopped Service"
    $STD uv pip install -r /opt/odysseus/requirements.txt --python=/opt/odysseus/venv/bin/python --upgrade
    $STD /opt/odysseus/venv/bin/python /opt/odysseus/setup.py
    msg_info "Starting Service"
    systemctl start odysseus
    msg_ok "Started Service"
    msg_ok "Updated Successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
