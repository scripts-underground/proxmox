#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Sportarr/Sportarr

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Sportarr"
var_tags="${var_tags:-arr}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    ffmpeg \
    gosu \
    sqlite3 \
    libicu-dev
  msg_ok "Installed Dependencies"

  SPORTARR_ARCH=$(uname -m)
  if [[ "$SPORTARR_ARCH" == "x86_64" ]]; then
    SPORTARR_ARCH="x64"
  elif [[ "$SPORTARR_ARCH" == "aarch64" ]]; then
    SPORTARR_ARCH="arm64"
  fi

  fetch_and_deploy_gh_release "sportarr" "Sportarr/Sportarr" "prebuild" "latest" "/opt/sportarr" "Sportarr-linux-${SPORTARR_ARCH}-*.tar.gz"

  msg_info "Creating Service"
  cat << EOF > /opt/sportarr/.env
Sportarr__DataPath="/opt/sportarr-data/config"
ASPNETCORE_URLS="http://*:1867"
ASPNETCORE_ENVIRONMENT="Production"
DOTNET_CLI_TELEMETRY_OPTOUT=1
DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false
LIBVA_DRIVER_NAME=iHD
EOF
  cat << EOF > /etc/systemd/system/sportarr.service
[Unit]
Description=Sportarr Service
After=network.target

[Service]
EnvironmentFile=/opt/sportarr/.env
WorkingDirectory=/opt/sportarr
ExecStart=/opt/sportarr/Sportarr
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now sportarr
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:1867${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/sportarr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "sportarr" "Sportarr/Sportarr"; then
    msg_info "Stopping Service"
    systemctl stop sportarr
    msg_ok "Stopped Service"

    SPORTARR_ARCH=$(uname -m)
    if [[ "$SPORTARR_ARCH" == "x86_64" ]]; then
      SPORTARR_ARCH="x64"
    elif [[ "$SPORTARR_ARCH" == "aarch64" ]]; then
      SPORTARR_ARCH="arm64"
    fi

    fetch_and_deploy_gh_release "sportarr" "Sportarr/Sportarr" "prebuild" "latest" "/opt/sportarr" "Sportarr-linux-${SPORTARR_ARCH}-*.tar.gz"

    msg_info "Starting Service"
    systemctl start sportarr
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
