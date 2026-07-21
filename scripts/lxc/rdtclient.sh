#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/rogerfar/rdt-client

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="RDTClient"
var_tags="${var_tags:-torrent}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
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
    "trixie"
  $STD apt install -y aspnetcore-runtime-10.0
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "rdt-client" "rogerfar/rdt-client" "prebuild" "latest" "/opt/rdtc" "RealDebridClient.zip"

  msg_info "Setting up rdtclient"
  cd /opt/rdtc || exit
  mkdir -p data/{db,downloads}
  sed -i 's#/data/db/#/opt/rdtc&#g' /opt/rdtc/appsettings.json
  msg_ok "Configured rdtclient"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/rdtc.service
[Unit]
Description=RdtClient Service

[Service]
WorkingDirectory=/opt/rdtc
ExecStart=/usr/bin/dotnet RdtClient.Web.dll
SyslogIdentifier=RdtClient
User=root

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now rdtc
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:6500${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/rdtc/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "rdt-client" "rogerfar/rdt-client"; then
    msg_info "Stopping Service"
    systemctl stop rdtc
    msg_ok "Stopped Service"

    msg_info "Creating backup"
    mkdir -p /opt/rdtc-backup
    cp -R /opt/rdtc/appsettings.json /opt/rdtc-backup/
    msg_ok "Backup created"

    fetch_and_deploy_gh_release "rdt-client" "rogerfar/rdt-client" "prebuild" "latest" "/opt/rdtc" "RealDebridClient.zip"
    cp -R /opt/rdtc-backup/appsettings.json /opt/rdtc/
    if dpkg-query -W aspnetcore-runtime-9.0 > /dev/null 2>&1; then
      $STD apt remove --purge -y aspnetcore-runtime-9.0
      ensure_dependencies aspnetcore-runtime-10.0
    fi
    rm -rf /opt/rdtc-backup

    msg_info "Starting Service"
    systemctl start rdtc
    msg_ok "Started Service"
    msg_ok "Updated Successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
