#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground-proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground-proxmox/main/LICENSE
# Source: https://github.com/fleetdm/fleet


# Read by the framework - shellcheck cannot see the caller\n# shellcheck disable=SC2034\nAPP="Fleet"
var_tags="${var_tags:-monitoring;device-management;security}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  setup_mysql

  MYSQL_DB_NAME="fleet" MYSQL_DB_USER="fleet" setup_mysql_db

  msg_info "Installing Dependencies"
  $STD apt install -y redis-server
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "fleet" "fleetdm/fleet" "prebuild" "latest" "/opt/fleet" "fleet_v*_linux.tar.gz"

  msg_info "Configuring Application"
  chmod +x /opt/fleet/fleet
  PRIVATE_KEY=$(openssl rand -hex 32)
  cat << EOF > /opt/fleet/.env
FLEET_MYSQL_ADDRESS=127.0.0.1:3306
FLEET_MYSQL_DATABASE=fleet
FLEET_MYSQL_USERNAME=fleet
FLEET_MYSQL_PASSWORD=${MYSQL_DB_PASS}
FLEET_SERVER_ADDRESS=0.0.0.0:8080
FLEET_SERVER_TLS=false
FLEET_SERVER_PRIVATE_KEY=${PRIVATE_KEY}
FLEET_REDIS_ADDRESS=127.0.0.1:6379
FLEET_LOGGING_JSON=true
EOF
  msg_ok "Configured Application"

  msg_info "Running Database Migrations"
  set -a && source /opt/fleet/.env && set +a
  $STD /opt/fleet/fleet prepare db --no-prompt
  msg_ok "Ran Database Migrations"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/fleet.service
[Unit]
Description=Fleet
After=network.target mysql.service redis-server.service
Requires=mysql.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/fleet
EnvironmentFile=/opt/fleet/.env
ExecStart=/opt/fleet/fleet serve
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now fleet redis-server
  msg_ok "Created Service"

  msg_info "Initializing Fleet"
  FLEET_ADMIN_EMAIL="admin@fleet.local"
  FLEET_ADMIN_PASS="$(openssl rand -hex 8)1!"
  ELAPSED=0
  until curl -sf "http://127.0.0.1:8080/healthz" > /dev/null 2>&1; do
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    [[ $ELAPSED -ge 60 ]] && break
  done
  SETUP_RESPONSE=$(curl -s -X POST "http://127.0.0.1:8080/api/v1/setup" \
    -H "Content-Type: application/json" \
    -d "{\"admin\":{\"admin\":true,\"email\":\"${FLEET_ADMIN_EMAIL}\",\"name\":\"Admin\",\"password\":\"${FLEET_ADMIN_PASS}\"},\"org_info\":{\"org_name\":\"Fleet\",\"org_logo_url\":\"\"},\"server_url\":\"http://127.0.0.1:8080\"}")
  FLEET_TOKEN=$(echo "${SETUP_RESPONSE}" | grep -o '"token":"[^"]*"' | cut -d'"' -f4) || true
  if [[ -n "${FLEET_TOKEN}" ]]; then
    curl -s -X PATCH "http://127.0.0.1:8080/api/latest/fleet/config" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${FLEET_TOKEN}" \
      -d "{\"server_settings\":{\"server_url\":\"http://${LOCAL_IP}:8080\"}}" > /dev/null
  fi
  cat << EOF >> /opt/fleet/.env
FLEET_ADMIN_EMAIL=${FLEET_ADMIN_EMAIL}
FLEET_ADMIN_PASSWORD=${FLEET_ADMIN_PASS}
EOF
  msg_ok "Initialized Fleet"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
  echo -e "${INFO}${YW} Admin Email:${CL} ${BGN}admin@fleet.local${CL}"
  echo -e "${INFO}${YW} Admin Password:${CL} ${BGN}Check inside the container: cat /opt/fleet/.env${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/fleet/fleet ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "fleet" "fleetdm/fleet"; then
    msg_info "Stopping Service"
    systemctl stop fleet
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "fleet" "fleetdm/fleet" "prebuild" "latest" "/opt/fleet" "fleet_v*_linux.tar.gz"
    chmod +x /opt/fleet/fleet

    msg_info "Running Database Migrations"
    set -a && source /opt/fleet/.env && set +a
    $STD /opt/fleet/fleet prepare db --no-prompt
    msg_ok "Ran Database Migrations"

    msg_info "Starting Service"
    systemctl start fleet
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# Dynamic URL resolved at runtime - shellcheck cannot follow\n# shellcheck disable=SC1090\nsource <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
