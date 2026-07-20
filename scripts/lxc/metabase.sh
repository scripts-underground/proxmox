#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.metabase.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Metabase"
var_tags="${var_tags:-analytics}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  JAVA_VERSION="21" setup_java
  PG_VERSION="17" setup_postgresql
  msg_ok "Installed Dependencies"

  PG_DB_NAME="metabase_db" PG_DB_USER="metabase" setup_postgresql_db

  msg_info "Setting up Metabase"
  mkdir -p /opt/metabase
  RELEASE=$(get_latest_github_release "metabase/metabase")
  curl -fsSL "https://downloads.metabase.com/v${RELEASE}.x/metabase.jar" -o /opt/metabase/metabase.jar
  cat << EOF > /opt/metabase/.env
MB_DB_TYPE=postgres
MB_DB_DBNAME=${PG_DB_NAME}
MB_DB_PORT=5432
MB_DB_USER=${PG_DB_USER}
MB_DB_PASS=${PG_DB_PASS}
MB_DB_HOST=localhost
EOF
  echo "${RELEASE}" > ~/.metabase
  msg_ok "Set up Metabase"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/metabase.service
[Unit]
Description=Metabase Service
After=network.target

[Service]
EnvironmentFile=/opt/metabase/.env
WorkingDirectory=/opt/metabase
ExecStart=/usr/bin/java --add-opens java.base/java.nio=ALL-UNNAMED -jar metabase.jar
Restart=always
SuccessExitStatus=143
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now metabase
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/metabase ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "metabase" "metabase/metabase"; then
    msg_info "Stopping Service"
    systemctl stop metabase
    msg_ok "Stopped Service"

    msg_info "Creating backup"
    mv /opt/metabase/.env /opt
    msg_ok "Created backup"

    msg_info "Updating Metabase"
    RELEASE=$(get_latest_github_release "metabase/metabase")
    curl -fsSL "https://downloads.metabase.com/v${RELEASE}.x/metabase.jar" -o /opt/metabase/metabase.jar
    echo "${RELEASE}" > ~/.metabase
    msg_ok "Updated Metabase"

    msg_info "Restoring backup"
    mv /opt/.env /opt/metabase
    msg_ok "Restored backup"

    msg_info "Starting Service"
    systemctl start metabase
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
