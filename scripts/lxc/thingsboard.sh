#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/thingsboard/thingsboard

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="ThingsBoard"
var_tags="${var_tags:-iot;platform}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    libharfbuzz0b \
    fontconfig \
    fonts-dejavu-core
  msg_ok "Installed Dependencies"

  JAVA_VERSION="17" setup_java
  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="thingsboard_db" PG_DB_USER="thingsboard" setup_postgresql_db
  fetch_and_deploy_gh_release "thingsboard" "thingsboard/thingsboard" "binary" "latest" "/tmp" "thingsboard-*.deb"

  msg_info "Configuring ThingsBoard"
  cat << EOF > /etc/thingsboard/conf/thingsboard.conf
# DB Configuration
export DATABASE_TS_TYPE=sql
export SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/${PG_DB_NAME}
export SPRING_DATASOURCE_USERNAME=${PG_DB_USER}
export SPRING_DATASOURCE_PASSWORD=${PG_DB_PASS}
# Specify partitioning size for timestamp key-value storage. Allowed values: DAYS, MONTHS, YEARS, INDEFINITE.
export SQL_POSTGRES_TS_KV_PARTITIONING=MONTHS
EOF
  systemctl daemon-reload
  msg_ok "Configured ThingsBoard"

  msg_info "Running ThingsBoard Installation Script"
  $STD /usr/share/thingsboard/bin/install/install.sh --loadDemo
  msg_ok "Ran Installation Script"

  msg_info "Starting ThingsBoard Service"
  systemctl enable -q --now thingsboard
  msg_ok "Started ThingsBoard Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /usr/share/thingsboard ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "thingsboard" "thingsboard/thingsboard"; then
    msg_info "Stopping Service"
    systemctl stop thingsboard
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "thingsboard" "thingsboard/thingsboard" "binary" "latest" "/tmp" "thingsboard-*.deb"

    msg_info "Running Database Upgrade"
    $STD /usr/share/thingsboard/bin/install/upgrade.sh
    msg_ok "Ran Database Upgrade"

    msg_info "Starting Service"
    systemctl start thingsboard
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
