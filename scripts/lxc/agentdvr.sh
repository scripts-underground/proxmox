#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.ispyconnect.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="AgentDVR"
var_tags="${var_tags:-dvr}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_arm64="${var_arm64:-yes}"
var_gpu="${var_gpu:-yes}"
var_unprivileged="${var_unprivileged:-0}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    apt-transport-https \
    alsa-utils \
    libxext-dev \
    fontconfig \
    libva-drm2
  msg_ok "Installed Dependencies"

  setup_hwaccel

  msg_info "Installing AgentDVR"
  mkdir -p /opt/agentdvr/agent
  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]] && AGENT_PLATFORM="Linux64" || AGENT_PLATFORM="LinuxARM64"
  RELEASE=$(curl -fsSL "https://www.ispyconnect.com/api/Agent/DownloadLocation4?platform=${AGENT_PLATFORM}&fromVersion=0" | grep -o 'https://.*\.zip')
  cd /opt/agentdvr/agent || exit
  curl -fsSL "$RELEASE" -o "$(basename "$RELEASE")"
  $STD unzip -o "Agent_${AGENT_PLATFORM}"*.zip
  chmod +x ./Agent
  echo "$RELEASE" > ~/.agentdvr
  rm -rf "Agent_${AGENT_PLATFORM}"*.zip
  msg_ok "Installed AgentDVR"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/AgentDVR.service
[Unit]
Description=AgentDVR

[Service]
WorkingDirectory=/opt/agentdvr/agent
ExecStart=/opt/agentdvr/agent/./Agent
Environment="MALLOC_TRIM_THRESHOLD_=100000"
SyslogIdentifier=AgentDVR
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now AgentDVR
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8090${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/agentdvr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]] && AGENT_PLATFORM="Linux64" || AGENT_PLATFORM="LinuxARM64"
  RELEASE=$(curl -fsSL "https://www.ispyconnect.com/api/Agent/DownloadLocation4?platform=${AGENT_PLATFORM}&fromVersion=0" | grep -o 'https://.*\.zip')
  if [[ "${RELEASE}" != "$(cat ~/.agentdvr 2> /dev/null)" ]] || [[ ! -f ~/.agentdvr ]]; then
    msg_info "Stopping service"
    systemctl stop AgentDVR
    msg_ok "Service stopped"

    msg_info "Updating AgentDVR"
    cd /opt/agentdvr/agent || exit
    curl -fsSL "$RELEASE" -o "$(basename "$RELEASE")"
    $STD unzip -o "Agent_${AGENT_PLATFORM}"*.zip
    chmod +x ./Agent
    echo "$RELEASE" > ~/.agentdvr
    rm -rf "Agent_${AGENT_PLATFORM}"*.zip
    msg_ok "Updated AgentDVR"

    msg_info "Starting service"
    systemctl start AgentDVR
    msg_ok "Service started"
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE}"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
