#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://infisical.com/

# shellcheck disable=SC2034
APP="Infisical"
var_tags="${var_tags:-auth}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    apt-transport-https \
    redis
  msg_ok "Installed Dependencies"

  PG_VERSION="17" setup_postgresql
  PG_DB_NAME="infisical_db" PG_DB_USER="infisical" setup_postgresql_db

  msg_info "Setting up Infisical Repository"
  setup_deb822_repo \
    "infisical" \
    "https://artifacts-infisical-core.infisical.com/infisical.gpg" \
    "https://artifacts-infisical-core.infisical.com/deb" \
    "stable"
  msg_ok "Setup Infisical repository"

  msg_info "Setting up Infisical"
  AUTH_SECRET="$(openssl rand -base64 32 | tr -d '\n')"
  ENC_KEY="$(openssl rand -hex 16 | tr -d '\n')"
  $STD apt install -y infisical-core
  mkdir -p /etc/infisical
  cat << EOF > /etc/infisical/infisical.rb
infisical_core['ENCRYPTION_KEY'] = '$ENC_KEY'
infisical_core['AUTH_SECRET'] = '$AUTH_SECRET'
infisical_core['HOST'] = '$LOCAL_IP'
infisical_core['DB_CONNECTION_URI'] = 'postgres://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}'
infisical_core['REDIS_URL'] = 'redis://localhost:6379'
EOF
  $STD infisical-ctl reconfigure
  msg_ok "Setup Infisical"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /etc/infisical ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping service"
  $STD infisical-ctl stop
  msg_ok "Service stopped"

  msg_info "Creating backup"
  [[ -f /opt/infisical_backup.sql ]] && rm -f /opt/infisical_backup.sql
  DB_PASS=$(grep -Po '(?<=^Password:\s).*' ~/infisical.creds | head -n1)
  PGPASSWORD=$DB_PASS pg_dump -U infisical -h localhost -d infisical_db > /opt/infisical_backup.sql
  msg_ok "Created backup"

  msg_info "Updating Infisical"
  $STD apt update
  $STD apt install -y infisical-core
  $STD infisical-ctl reconfigure
  msg_ok "Updated Infisical"

  msg_info "Starting service"
  infisical-ctl start
  msg_ok "Started service"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
