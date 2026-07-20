#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: vhsdream
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/dotnetfactory/fluid-calendar

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="fluid-calendar"
var_tags="${var_tags:-calendar;tasks}"
var_cpu="${var_cpu:-3}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-7}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y build-essential
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" setup_nodejs

  fetch_and_deploy_gh_release "fluid-calendar" "dotnetfactory/fluid-calendar" "tarball"

  msg_info "Setting up Fluid Calendar"
  cd /opt/fluid-calendar || exit
  NEXTAUTH_SECRET="$(openssl rand -hex 32)"
  cat << EOF > /opt/fluid-calendar/.env
DATABASE_URL="file:./data/fluid-calendar.db"
NEXTAUTH_URL="http://0.0.0.0:3000"
NEXT_PUBLIC_APP_URL="http://0.0.0.0:3000"
NEXTAUTH_SECRET="${NEXTAUTH_SECRET}"
NEXT_PUBLIC_SITE_URL="http://0.0.0.0:3000"
NEXT_PUBLIC_ENABLE_SAAS_FEATURES=false
HOSTNAME=0.0.0.0
PORT=3000
EOF
  mkdir -p /opt/fluid-calendar/data
  export NEXT_TELEMETRY_DISABLED=1
  $STD npm install --legacy-peer-deps
  $STD npm run prisma:generate
  $STD npx prisma migrate deploy
  $STD npm run build:os
  msg_ok "Set up Fluid Calendar"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/fluid-calendar.service
[Unit]
Description=Fluid Calendar Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/fluid-calendar
EnvironmentFile=/opt/fluid-calendar/.env
ExecStart=/usr/bin/npm start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now fluid-calendar
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

  if [[ ! -d /opt/fluid-calendar ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  ensure_dependencies build-essential
  NODE_VERSION="24" setup_nodejs

  if check_for_gh_release "fluid-calendar" "dotnetfactory/fluid-calendar"; then
    msg_info "Stopping Service"
    systemctl stop fluid-calendar
    msg_ok "Stopped Service"

    cp /opt/fluid-calendar/.env /opt/fluid.env
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "fluid-calendar" "dotnetfactory/fluid-calendar" "tarball"
    mv /opt/fluid.env /opt/fluid-calendar/.env

    msg_info "Updating Fluid Calendar"
    cd /opt/fluid-calendar || exit
    export NEXT_TELEMETRY_DISABLED=1
    $STD npm install --legacy-peer-deps
    $STD npm run prisma:generate
    $STD npx prisma migrate deploy
    $STD npm run build:os
    msg_ok "Updated Fluid Calendar"

    msg_info "Starting Service"
    systemctl start fluid-calendar
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
