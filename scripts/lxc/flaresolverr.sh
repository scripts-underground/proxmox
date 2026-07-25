#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster) | Co-Author: remz1337
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/FlareSolverr/FlareSolverr

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="FlareSolverr"
var_tags="${var_tags:-proxy}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt-get install -y \
    apt-transport-https \
    xvfb
  msg_ok "Installed Dependencies"

  msg_info "Installing Chrome"
  setup_deb822_repo \
    "google-chrome" \
    "https://dl.google.com/linux/linux_signing_key.pub" \
    "https://dl.google.com/linux/chrome/deb/" \
    "stable"
  $STD apt update
  $STD apt install -y google-chrome-stable
  if [ -f /etc/apt/sources.list.d/google-chrome.list ]; then
    rm /etc/apt/sources.list.d/google-chrome.list
  fi
  msg_ok "Installed Chrome"

  fetch_and_deploy_gh_release "flaresolverr" "FlareSolverr/FlareSolverr" "prebuild" "latest" "/opt/flaresolverr" "flaresolverr_linux_x64.tar.gz"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/flaresolverr.service
[Unit]
Description=FlareSolverr
After=network.target
[Service]
SyslogIdentifier=flaresolverr
Restart=always
RestartSec=5
Type=simple
Environment="LOG_LEVEL=info"
Environment="CAPTCHA_SOLVER=none"
WorkingDirectory=/opt/flaresolverr
ExecStart=/opt/flaresolverr/flaresolverr
TimeoutStopSec=30
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now flaresolverr
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8191${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/systemd/system/flaresolverr.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if [[ $(grep -E '^VERSION_ID=' /etc/os-release) == *"12"* ]]; then
    msg_error "Wrong Debian version detected!"
    msg_error "You must upgrade your LXC to Debian Trixie before updating."
    exit
  fi
  if check_for_gh_release "flaresolverr" "FlareSolverr/FlareSolverr"; then
    msg_info "Stopping service"
    systemctl stop flaresolverr
    msg_ok "Stopped service"

    rm -rf /opt/flaresolverr
    fetch_and_deploy_gh_release "flaresolverr" "FlareSolverr/FlareSolverr" "prebuild" "latest" "/opt/flaresolverr" "flaresolverr_linux_x64.tar.gz"

    msg_info "Starting service"
    systemctl start flaresolverr
    msg_ok "Started service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
