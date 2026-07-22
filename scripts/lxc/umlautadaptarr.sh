#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: elvito
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/PCJones/UmlautAdaptarr

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="UmlautAdaptarr"
var_tags="${var_tags:-arr}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  setup_deb822_repo \
    "microsoft" \
    "https://packages.microsoft.com/keys/microsoft.asc" \
    "https://packages.microsoft.com/debian/12/prod/" \
    "bookworm" \
    "main"
  $STD apt install -y \
    dotnet-sdk-8.0 \
    aspnetcore-runtime-8.0
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "UmlautAdaptarr" "PCJones/Umlautadaptarr" "prebuild" "latest" "/opt/UmlautAdaptarr" "linux-x64.zip"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/umlautadaptarr.service
[Unit]
Description=UmlautAdaptarr Service
After=network.target

[Service]
WorkingDirectory=/opt/UmlautAdaptarr
ExecStart=/usr/bin/dotnet /opt/UmlautAdaptarr/UmlautAdaptarr.dll --urls=http://0.0.0.0:5005
Restart=always
User=root
Group=root
Environment=ASPNETCORE_ENVIRONMENT=Production

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now umlautadaptarr
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5005${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/UmlautAdaptarr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "UmlautAdaptarr" "PCJones/Umlautadaptarr"; then
    msg_info "Stopping Service"
    systemctl stop umlautadaptarr
    msg_ok "Stopped Service"

    create_backup /opt/UmlautAdaptarr/appsettings.json
    fetch_and_deploy_gh_release "UmlautAdaptarr" "PCJones/Umlautadaptarr" "prebuild" "latest" "/opt/UmlautAdaptarr" "linux-x64.zip"
    restore_backup

    msg_info "Starting Service"
    systemctl start umlautadaptarr
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
