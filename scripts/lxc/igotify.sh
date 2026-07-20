#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: pfassina
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/androidseb25/iGotify-Notification-Assistent

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="iGotify"
var_tags="${var_tags:-notifications;gotify}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  setup_deb822_repo \
    "microsoft" \
    "https://packages.microsoft.com/keys/microsoft-2025.asc" \
    "https://packages.microsoft.com/debian/13/prod/" \
    "trixie" \
    "main"
  $STD apt install -y aspnetcore-runtime-10.0
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "igotify" "androidseb25/iGotify-Notification-Assistent" "prebuild" "latest" "/opt/igotify" "iGotify-Notification-Service-$(get_system_arch)-v*.zip"

  msg_info "Creating Service"
  cat << EOF > /opt/igotify/.env
ASPNETCORE_URLS=http://0.0.0.0:80
ASPNETCORE_ENVIRONMENT=Production
GOTIFY_DEFAULTUSER_PASS=
GOTIFY_URLS=
GOTIFY_CLIENT_TOKENS=
SECNTFY_TOKENS=
EOF
  cat << EOF > /etc/systemd/system/igotify.service
[Unit]
Description=iGotify Notification Service
After=network.target

[Service]
EnvironmentFile=/opt/igotify/.env
WorkingDirectory=/opt/igotify
ExecStart=/usr/bin/dotnet "/opt/igotify/iGotify Notification Assist.dll"
Restart=always
RestartSec=10
KillSignal=SIGINT
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now igotify
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/igotify ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "igotify" "androidseb25/iGotify-Notification-Assistent"; then
    msg_info "Stopping Service"
    systemctl stop igotify
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration"
    cp /opt/igotify/.env /opt/igotify.env.bak
    msg_ok "Backed up Configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "igotify" "androidseb25/iGotify-Notification-Assistent" "prebuild" "latest" "/opt/igotify" "iGotify-Notification-Service-$(get_system_arch)-v*.zip"

    msg_info "Restoring Configuration"
    cp /opt/igotify.env.bak /opt/igotify/.env
    rm -f /opt/igotify.env.bak
    msg_ok "Restored Configuration"

    msg_info "Starting Service"
    systemctl start igotify
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
