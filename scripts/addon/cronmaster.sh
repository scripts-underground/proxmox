#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/fccview/cronmaster

REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

APP="CronMaster"
APP_TYPE="addon"
INSTALL_PATH="/opt/cronmaster"
CONFIG_PATH="/opt/cronmaster/.env"
SERVICE_PATH="/etc/systemd/system/cronmaster.service"
DEFAULT_PORT=3000

function header_info {
  clear
  cat << "EOF"
   ______                __  ___           __
  / ____/________  ____ /  |/  /___ ______/ /____  _____
 / /   / ___/ __ \/ __ \/ /|_/ / __ `/ ___/ __/ _ \/ ___/
/ /___/ /  / /_/ / / / / /  / / /_/ (__  ) /_/  __/ /
\____/_/   \____/_/ /_/_/  /_/\__,_/____/\__/\___/_/

EOF
}

if ! grep -qE 'ID=debian|ID=ubuntu' /etc/os-release 2> /dev/null; then
  echo -e "${CROSS} Unsupported OS detected. This script only supports Debian and Ubuntu."
  exit 238
fi

function install_script() {
  if command -v node &> /dev/null; then
    msg_ok "Node.js already installed ($(node -v))"
  else
    NODE_VERSION="22" setup_nodejs
  fi

  fetch_and_deploy_gh_release "cronmaster" "fccview/cronmaster" "prebuild" "latest" "$INSTALL_PATH" "cronmaster_*_prebuild.tar.gz"

  local AUTH_PASS
  AUTH_PASS="$(openssl rand -base64 18 | cut -c1-13)"

  msg_info "Creating configuration"
  cat << EOF > "$CONFIG_PATH"
NODE_ENV=production
AUTH_PASSWORD=${AUTH_PASS}
PORT=${DEFAULT_PORT}
HOSTNAME=0.0.0.0
NEXT_TELEMETRY_DISABLED=1
EOF
  chmod 600 "$CONFIG_PATH"
  msg_ok "Created configuration"

  msg_info "Creating service"
  cat << EOF > "$SERVICE_PATH"
[Unit]
Description=CronMaster Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_PATH}
EnvironmentFile=${CONFIG_PATH}
ExecStart=/usr/bin/node ${INSTALL_PATH}/server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now cronmaster
  msg_ok "Created and started service"

  msg_info "Creating update script"
  cat << 'UPDATEEOF' > /usr/local/bin/update_cronmaster
#!/usr/bin/env bash
# CronMaster Update Script
CRONMASTER_ACTION=update bash -c "$(curl -fsSL https://raw.githubusercontent.com/scripts-underground/proxmox/main/tools/addon/cronmaster.sh)"
UPDATEEOF
  chmod +x /usr/local/bin/update_cronmaster
  msg_ok "Created update script (/usr/local/bin/update_cronmaster)"
}

function update_script() {
  if check_for_gh_release "cronmaster" "fccview/cronmaster"; then
    msg_info "Stopping service"
    systemctl stop cronmaster.service &> /dev/null || true
    msg_ok "Stopped service"

    msg_info "Backing up configuration"
    cp "$CONFIG_PATH" /tmp/cronmaster.env.bak 2> /dev/null || true
    msg_ok "Backed up configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "cronmaster" "fccview/cronmaster" "prebuild" "latest" "$INSTALL_PATH" "cronmaster_*_prebuild.tar.gz"

    msg_info "Restoring configuration"
    cp /tmp/cronmaster.env.bak "$CONFIG_PATH" 2> /dev/null || true
    rm -f /tmp/cronmaster.env.bak
    msg_ok "Restored configuration"

    msg_info "Updating update script"
    cat << 'UPDATEEOF' > /usr/local/bin/update_cronmaster
#!/usr/bin/env bash
# CronMaster Update Script
CRONMASTER_ACTION=update bash -c "$(curl -fsSL https://raw.githubusercontent.com/scripts-underground/proxmox/main/tools/addon/cronmaster.sh)"
UPDATEEOF
    chmod +x /usr/local/bin/update_cronmaster
    msg_ok "Updated update script"

    msg_info "Starting service"
    systemctl start cronmaster
    msg_ok "Started service"
    msg_ok "Updated successfully"
  fi
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"
  systemctl disable --now cronmaster.service &> /dev/null || true
  rm -f "$SERVICE_PATH"
  rm -rf "$INSTALL_PATH"
  rm -f "/usr/local/bin/update_cronmaster"
  rm -f "$HOME/.cronmaster"
  rm -f "/root/cronmaster.creds"
  msg_ok "${APP} has been uninstalled"
}

function post_install_script() {
  local CREDS_FILE="/root/cronmaster.creds"
  cat << EOF > "$CREDS_FILE"
CronMaster Credentials
======================
Password: ${AUTH_PASS}

Web UI: http://${LOCAL_IP}:${DEFAULT_PORT}
EOF
  echo ""
  msg_ok "${APP} is reachable at: ${BL}http://${LOCAL_IP}:${DEFAULT_PORT}${CL}"
  msg_ok "Credentials saved to: ${BL}${CREDS_FILE}${CL}"
  echo ""
}

# framework bootstrap
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon")
