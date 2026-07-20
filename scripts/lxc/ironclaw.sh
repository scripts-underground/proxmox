#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/nearai/ironclaw

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="IronClaw"
var_tags="${var_tags:-ai;agent;security}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y openssl
  msg_ok "Installed Dependencies"

  msg_info "Setting up PostgreSQL"
  PG_VERSION="17" PG_MODULES="pgvector" setup_postgresql
  PG_DB_NAME="ironclaw" PG_DB_USER="ironclaw" PG_DB_EXTENSIONS="vector" setup_postgresql_db
  msg_ok "Set up PostgreSQL"

  fetch_and_deploy_gh_release "ironclaw-bin" "nearai/ironclaw" "prebuild" "latest" "/usr/local/bin" \
    "ironclaw-$(get_system_arch)-unknown-linux-gnu.tar.gz"
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
DATABASE_URL=postgresql://ironclaw:${PG_DB_PASS}@localhost:5432/ironclaw?sslmode=disable
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
  /usr/local/bin/ironclaw --no-onboard config set database_url "postgresql://ironclaw:${PG_DB_PASS}@localhost:5432/ironclaw?sslmode=disable" > /dev/null
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
  cat << EOF > /etc/systemd/system/ironclaw.service
[Unit]
Description=IronClaw AI Agent
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
EnvironmentFile=/root/.ironclaw/.env
ExecStart=/usr/local/bin/ironclaw
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now ironclaw
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Next Steps:${CL}"
  echo -e "${TAB}1. Configure remaining settings:${CL}"
  echo -e "${TAB}${TAB}${BGN}/usr/local/bin/ironclaw onboard${CL}"
  echo -e "${TAB}2. Access the Web UI at:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
  echo -e "${TAB}${INFO}${YW} Use the Gateway Authentication Token from:${CL}"
  echo -e "${TAB}${BGN}cat /root/.ironclaw/gateway.creds${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /usr/local/bin/ironclaw ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "ironclaw-bin" "nearai/ironclaw"; then
    msg_info "Stopping Service"
    systemctl stop ironclaw
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration"
    cp /root/.ironclaw/.env /root/ironclaw.env.bak
    msg_ok "Backed up Configuration"

    fetch_and_deploy_gh_release "ironclaw-bin" "nearai/ironclaw" "prebuild" "latest" "/usr/local/bin" \
      "ironclaw-$(get_system_arch)-unknown-linux-gnu.tar.gz"
    chmod +x /usr/local/bin/ironclaw

    msg_info "Restoring Configuration"
    cp /root/ironclaw.env.bak /root/.ironclaw/.env
    rm -f /root/ironclaw.env.bak
    msg_ok "Restored Configuration"

    msg_info "Starting Service"
    systemctl start ironclaw
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
