#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/nearai/ironclaw

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-IronClaw"
var_tags="${var_tags:-ai;agent;alpine}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apk add openssl dbus gnome-keyring
  msg_ok "Installed Dependencies"

  msg_info "Installing PostgreSQL"
  $STD apk add postgresql17 postgresql17-openrc postgresql-pgvector postgresql-common
  $STD rc-service postgresql setup
  $STD rc-update add postgresql default
  $STD rc-service postgresql start
  msg_ok "Installed PostgreSQL"

  msg_info "Setting up Database"
  PG_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
  $STD su -s /bin/sh postgres -c "psql -c \"CREATE ROLE ironclaw WITH LOGIN PASSWORD '${PG_PASS}';\""
  $STD su -s /bin/sh postgres -c "psql -c \"CREATE DATABASE ironclaw WITH OWNER ironclaw;\""
  $STD su -s /bin/sh postgres -c "psql -d ironclaw -c \"CREATE EXTENSION IF NOT EXISTS vector;\""
  msg_ok "Set up Database"

  fetch_and_deploy_gh_release "ironclaw-bin" "nearai/ironclaw" "prebuild" "latest" "/usr/local/bin" \
    "ironclaw-$(uname -m)-unknown-linux-musl.tar.gz"
  chmod +x /usr/local/bin/ironclaw

  msg_info "Configuring Environment"
  GATEWAY_TOKEN=$(openssl rand -hex 32)
  mkdir -p /root/.ironclaw
  cat << EOF > /root/.ironclaw/gateway.creds
Gateway-Token
Token: ${GATEWAY_TOKEN}
EOF
  cat << EOF > /root/.ironclaw/.env
DATABASE_BACKEND=postgres
DATABASE_URL=postgresql://ironclaw:${PG_PASS}@localhost:5432/ironclaw?sslmode=disable
GATEWAY_ENABLED=true
GATEWAY_HOST=0.0.0.0
GATEWAY_PORT=3000
GATEWAY_AUTH_TOKEN=${GATEWAY_TOKEN}
CLI_ENABLED=false
RUST_LOG=ironclaw=info,tower_http=info
EOF
  chmod 600 /root/.ironclaw/.env
  msg_ok "Configured Environment"

  msg_info "Configuring IronClaw"
  /usr/local/bin/ironclaw --no-onboard config set database_backend postgres > /dev/null
  /usr/local/bin/ironclaw --no-onboard config set database_url "postgresql://ironclaw:${PG_PASS}@localhost:5432/ironclaw?sslmode=disable" > /dev/null
  /usr/local/bin/ironclaw --no-onboard config set channels.gateway_enabled true > /dev/null
  /usr/local/bin/ironclaw --no-onboard config set channels.gateway_host 0.0.0.0 > /dev/null
  /usr/local/bin/ironclaw --no-onboard config set channels.gateway_port 3000 > /dev/null
  /usr/local/bin/ironclaw --no-onboard config set channels.gateway_auth_token "${GATEWAY_TOKEN}" > /dev/null
  /usr/local/bin/ironclaw --no-onboard config set channels.cli_enabled false > /dev/null
  /usr/local/bin/ironclaw --no-onboard config set secrets_master_key_source none > /dev/null
  sleep 5
  sed -i '/SECRETS_MASTER_KEY/d' /root/.ironclaw/.env
  msg_ok "Configured IronClaw"

  msg_info "Creating Service"
  cat << EOF > /etc/init.d/ironclaw
#!/sbin/openrc-run

name="IronClaw"
description="IronClaw AI Agent"
command="/usr/bin/dbus-run-session"
command_args="/usr/local/bin/ironclaw"
command_background=true
pidfile="/run/ironclaw.pid"
directory="/root"
supervise_daemon_args="--env-file /root/.ironclaw/.env"

depend() {
  need net postgresql
}
EOF
  chmod +x /etc/init.d/ironclaw
  $STD rc-update add ironclaw default
  $STD rc-service ironclaw start
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
  echo -e "${INFO}${YW} Use the Gateway Authentication Token from:${CL}"
  echo -e "${TAB}${BGN}cat /root/.ironclaw/gateway.creds${CL}"
}

function update_script() {
  header_info

  if [[ ! -f /usr/local/bin/ironclaw ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "ironclaw-bin" "nearai/ironclaw"; then
    msg_info "Stopping Service"
    rc-service ironclaw stop 2> /dev/null || true
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration"
    cp /root/.ironclaw/.env /root/ironclaw.env.bak
    msg_ok "Backed up Configuration"

    fetch_and_deploy_gh_release "ironclaw-bin" "nearai/ironclaw" "prebuild" "latest" "/usr/local/bin" \
      "ironclaw-$(uname -m)-unknown-linux-musl.tar.gz"
    chmod +x /usr/local/bin/ironclaw

    msg_info "Restoring Configuration"
    cp /root/ironclaw.env.bak /root/.ironclaw/.env
    rm -f /root/ironclaw.env.bak
    msg_ok "Restored Configuration"

    msg_info "Starting Service"
    rc-service ironclaw start
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
