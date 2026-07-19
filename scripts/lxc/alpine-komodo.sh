#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://komo.do/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-Komodo"
var_tags="${var_tags:-docker;alpine}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-10}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apk add openssl
  msg_ok "Installed Dependencies"

  msg_info "Installing Docker"
  $STD apk add docker docker-cli-compose
  $STD rc-service docker start
  $STD rc-update add docker default
  msg_ok "Installed Docker"

  msg_info "Waiting for Docker"
  sleep 10
  $STD docker info
  msg_ok "Docker is running"

  msg_info "Creating install directory"
  mkdir -p /opt/komodo
  msg_ok "Created install directory"

  msg_info "Downloading Docker Compose file"
  curl -fsSL "https://raw.githubusercontent.com/moghtech/komodo/main/compose/mongo.compose.yaml" -o /opt/komodo/mongo.compose.yaml
  msg_ok "Downloaded Docker Compose file"

  msg_info "Configuring environment"
  curl -fsSL "https://raw.githubusercontent.com/moghtech/komodo/main/compose/compose.env" -o /opt/komodo/compose.env

  DB_PASSWORD=$(openssl rand -base64 16 | tr -d '/+=')
  ADMIN_PASSWORD=$(openssl rand -base64 8 | tr -d '/+=')
  WEBHOOK_SECRET=$(openssl rand -base64 24 | tr -d '/+=')
  JWT_SECRET=$(openssl rand -base64 24 | tr -d '/+=')

  sed -i "s/^KOMODO_DATABASE_USERNAME=.*/KOMODO_DATABASE_USERNAME=komodo_admin/" /opt/komodo/compose.env
  sed -i "s/^KOMODO_DATABASE_PASSWORD=.*/KOMODO_DATABASE_PASSWORD=${DB_PASSWORD}/" /opt/komodo/compose.env
  sed -i "s/^KOMODO_INIT_ADMIN_PASSWORD=changeme/KOMODO_INIT_ADMIN_PASSWORD=${ADMIN_PASSWORD}/" /opt/komodo/compose.env
  sed -i "s/^KOMODO_WEBHOOK_SECRET=.*/KOMODO_WEBHOOK_SECRET=${WEBHOOK_SECRET}/" /opt/komodo/compose.env
  sed -i "s/^KOMODO_JWT_SECRET=.*/KOMODO_JWT_SECRET=${JWT_SECRET}/" /opt/komodo/compose.env
  msg_ok "Configured environment"

  msg_info "Starting Komodo"
  cd /opt/komodo || exit
  $STD docker compose -p komodo -f /opt/komodo/mongo.compose.yaml --env-file /opt/komodo/compose.env up -d
  msg_ok "Started Komodo"

  {
    echo "Komodo Credentials"
    echo ""
    echo "Admin User    : admin"
    echo "Admin Password: ${ADMIN_PASSWORD}"
  } > ~/komodo.creds

  msg_info "Credentials saved to ~/komodo.creds"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9120${CL}"
  echo ""
  echo -e "  Komodo Credentials"
  echo -e "  =================="
  echo -e "  User    : admin"
  echo -e "  Password: See ~/komodo.creds"
}

function update_script() {
  header_info
  if [[ ! -d /opt/komodo ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating Alpine Packages"
  $STD apk -U upgrade
  msg_ok "Updated Alpine Packages"

  COMPOSE_FILE=$(find /opt/komodo -maxdepth 1 -type f -name '*.compose.yaml' ! -name 'compose.env' | head -n1)
  if [[ -z "$COMPOSE_FILE" ]]; then
    msg_error "No valid compose file found in /opt/komodo!"
    exit
  fi

  msg_info "Updating Komodo"
  $STD docker compose -p komodo -f "$COMPOSE_FILE" --env-file /opt/komodo/compose.env pull
  $STD docker compose -p komodo -f "$COMPOSE_FILE" --env-file /opt/komodo/compose.env up -d
  msg_ok "Updated Komodo"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
