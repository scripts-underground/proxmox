#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/s1t5/mail-archiver

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Mail-Archiver"
var_tags="${var_tags:-mail;archive}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y libgssapi-krb5-2 unzip
  msg_ok "Installed Dependencies"

  msg_info "Setting up PostgreSQL"
  PG_VERSION="17" setup_postgresql
  PG_DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
  PG_DB_NAME="mailarchiver" PG_DB_USER="mailarchiver" PG_DB_PASS="$PG_DB_PASS" setup_postgresql_db
  msg_ok "Set up PostgreSQL"

  msg_info "Installing .NET SDK 10.0"
  if [[ "$(get_system_arch)" == "arm64" ]]; then
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
    $STD bash /tmp/dotnet-install.sh --channel 10.0 --install-dir /usr/lib/dotnet10
    ln -sf /usr/lib/dotnet10/dotnet /usr/bin/dotnet
    rm -f /tmp/dotnet-install.sh
  else
    setup_deb822_repo "microsoft" \
      "https://packages.microsoft.com/keys/microsoft-2025.asc" \
      "https://packages.microsoft.com/debian/13/prod/" \
      "trixie"
    $STD apt install -y dotnet-sdk-10.0
  fi
  msg_ok "Installed .NET SDK 10.0"

  fetch_and_deploy_gh_release "mail-archiver" "s1t5/mail-archiver" "tarball"

  msg_info "Building Mail-Archiver"
  mv /opt/mail-archiver /opt/mail-archiver-src
  cd /opt/mail-archiver-src || exit
  $STD dotnet restore
  $STD dotnet publish -c Release -o /opt/mail-archiver
  rm -rf /opt/mail-archiver-src
  msg_ok "Built Mail-Archiver"

  msg_info "Configuring Mail-Archiver"
  cat << EOF > /opt/mail-archiver/.env
ConnectionStrings__DefaultConnection=Host=localhost;Database=mailarchiver;Username=mailarchiver;Password=${PG_DB_PASS}
Authentication__Username=admin
Authentication__Password=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | cut -c1-16)
TimeZone__DisplayTimeZoneId=Etc/UCT
EOF
  chmod 600 /opt/mail-archiver/.env
  msg_ok "Configured Mail-Archiver"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/mail-archiver.service
[Unit]
Description=Mail-Archiver Service
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/mail-archiver
EnvironmentFile=/opt/mail-archiver/.env
ExecStart=/usr/bin/dotnet /opt/mail-archiver/MailArchiver.dll
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now mail-archiver
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/mail-archiver ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  ensure_dependencies libgssapi-krb5-2

  if check_for_gh_release "mail-archiver" "s1t5/mail-archiver"; then
    msg_info "Stopping Mail-Archiver"
    systemctl stop mail-archiver
    msg_ok "Stopped Mail-Archiver"

    msg_info "Creating Backup"
    cp /opt/mail-archiver/appsettings.json /opt/mail-archiver/.env /opt/
    [[ -d /opt/mail-archiver/DataProtection-Keys ]] && cp -r /opt/mail-archiver/DataProtection-Keys /opt
    msg_ok "Created Backup"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "mail-archiver" "s1t5/mail-archiver" "tarball"

    msg_info "Updating Mail-Archiver"
    mv /opt/mail-archiver /opt/mail-archiver-build
    cd /opt/mail-archiver-build || exit
    $STD dotnet restore
    $STD dotnet publish -c Release -o /opt/mail-archiver
    rm -rf /opt/mail-archiver-build
    msg_ok "Updated Mail-Archiver"

    msg_info "Restoring Backup"
    cp /opt/appsettings.json /opt/.env /opt/mail-archiver
    [[ -d /opt/DataProtection-Keys ]] && cp -r /opt/DataProtection-Keys /opt/mail-archiver/
    msg_ok "Restored Backup"

    msg_info "Starting Mail-Archiver"
    systemctl start mail-archiver
    msg_ok "Started Mail-Archiver"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
