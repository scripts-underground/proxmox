#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: omernaveedxyz
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://miniflux.app/

# shellcheck disable=SC2034
APP="Miniflux"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y postgresql-client
  msg_ok "Installed Dependencies"

  PG_VERSION="17" setup_postgresql
  PG_DB_NAME="miniflux_db" PG_DB_USER="miniflux" PG_DB_GRANT_SUPERUSER="true" setup_postgresql_db

  fetch_and_deploy_gh_release "miniflux" "miniflux/v2" "binary" "latest"

  msg_info "Configuring Miniflux"
  ADMIN_NAME="admin"
  ADMIN_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)"
  cat << EOF > /etc/miniflux.conf
# See https://miniflux.app/docs/configuration.html
DATABASE_URL=user=$PG_DB_USER password=$PG_DB_PASS dbname=$PG_DB_NAME sslmode=disable
CREATE_ADMIN=1
ADMIN_USERNAME=$ADMIN_NAME
ADMIN_PASSWORD=$ADMIN_PASS
LISTEN_ADDR=0.0.0.0:8080
EOF
  cat << EOF > ~/miniflux.creds
ADMIN_USERNAME: $ADMIN_NAME
ADMIN_PASSWORD: $ADMIN_PASS
EOF
  $STD miniflux -migrate -config-file /etc/miniflux.conf
  systemctl enable -q --now miniflux
  msg_ok "Configured Miniflux"
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
  if ! systemctl -q is-enabled miniflux 2> /dev/null; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "miniflux" "miniflux/v2"; then
    msg_info "Stopping Service"
    $STD miniflux -flush-sessions -config-file /etc/miniflux.conf
    systemctl stop miniflux
    msg_ok "Service Stopped"

    fetch_and_deploy_gh_release "miniflux" "miniflux/v2" "binary" "latest"

    msg_info "Updating Miniflux"
    $STD miniflux -migrate -config-file /etc/miniflux.conf
    msg_ok "Updated Miniflux"
    msg_info "Starting Service"
    systemctl start miniflux
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
