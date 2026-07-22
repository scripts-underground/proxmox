#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.microsoft.com/en-us/sql-server/sql-server-2025

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="SQL Server 2025"
var_tags="${var_tags:-sql;database}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-0}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y coreutils
  msg_ok "Installed Dependencies"

  msg_info "Setting up SQL Server 2025 Repository"
  setup_deb822_repo \
    "mssql-server-2025" \
    "https://packages.microsoft.com/keys/microsoft.asc" \
    "https://packages.microsoft.com/ubuntu/24.04/mssql-server-2025" \
    "noble" \
    "main"
  msg_ok "Repository configured"

  msg_info "Installing SQL Server 2025"
  $STD apt install -y mssql-server
  msg_ok "Installed SQL Server 2025"

  msg_info "Installing SQL Server Tools"
  export DEBIAN_FRONTEND=noninteractive
  export ACCEPT_EULA=Y
  setup_deb822_repo \
    "mssql-release" \
    "https://packages.microsoft.com/keys/microsoft.asc" \
    "https://packages.microsoft.com/ubuntu/24.04/prod" \
    "noble" \
    "main"
  $STD apt install -y \
    mssql-tools18 \
    unixodbc-dev
  echo 'export PATH="$PATH:/opt/mssql-tools18/bin"' >> ~/.bash_profile
  # shellcheck disable=SC1090
  # ~/.bash_profile is created above - shellcheck cannot follow
  source ~/.bash_profile
  msg_ok "Installed SQL Server Tools"

  msg_info "Starting SQL Server Service"
  systemctl enable -q --now mssql-server
  msg_ok "Service started"

  msg_info "Cleaning up"
  rm -f /etc/profile.d/debuginfod.sh /etc/profile.d/debuginfod.csh
  msg_ok "Cleaned up"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following IP:${CL}"
  echo -e "${GATEWAY}${BGN}${IP}:1433${CL}"
  echo ""
  echo -e "${INFO}${YW}Run '/opt/mssql/bin/mssql-conf setup' to configure SQL Server if not already done.${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/mssql ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating SQL Server 2025"
  rm -f /etc/profile.d/debuginfod.sh /etc/profile.d/debuginfod.csh
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
