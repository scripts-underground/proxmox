#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: vhsdream
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/intri-in/manage-my-damn-life-nextjs

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Manage My Damn Life"
var_tags="${var_tags:-calendar;tasks}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y build-essential
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" setup_nodejs
  setup_mariadb

  msg_info "Setting up Database"
  DB_NAME="mmdl"
  DB_USER="mmdl"
  DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  $STD mariadb -u root -e "CREATE DATABASE $DB_NAME;"
  $STD mariadb -u root -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED by '$DB_PASS';"
  $STD mariadb -u root -e "GRANT ALL ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"
  cat << EOF > /root/mmdl.creds
Manage My Damn Life Credentials
Database User: $DB_USER
Database Password: $DB_PASS
Database Name: $DB_NAME
EOF
  msg_ok "Set up Database"

  fetch_and_deploy_gh_release "mmdl" "intri-in/manage-my-damn-life-nextjs" "tarball"

  msg_info "Configuring ${APP}"
  cp /opt/mmdl/sample.env.local /opt/mmdl/.env
  sed -i -e 's|db|localhost|' \
    -e "s|myuser|${DB_USER}|" \
    -e "s|mypassword|${DB_PASS}|" \
    -e 's|5433|3306|' \
    -e 's|DB_DIALECT=postgres|DB_DIALECT=mysql|' \
    -e "s|sample_install_mmdm|${DB_NAME}|" \
    -e "s|=PASSWORD|=$(openssl rand -base64 40 | tr -dc 'a-zA-Z0-9' | head -c40)|" \
    /opt/mmdl/.env
  cd /opt/mmdl || exit
  export NEXT_TELEMETRY_DISABLED=1
  export CI="true"
  $STD npm install
  $STD npm run migrate
  $STD npm run build
  msg_ok "Configured ${APP}"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/mmdl.service
[Unit]
Description=${APP} Service
After=network.target mariadb.service

[Service]
WorkingDirectory=/opt/mmdl
EnvironmentFile=/opt/mmdl/.env
ExecStart=/usr/bin/npm run start
Restart=on-abnormal

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now mmdl
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

  if [[ ! -d /opt/mmdl ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  setup_mariadb
  if check_for_gh_release "mmdl" "intri-in/manage-my-damn-life-nextjs"; then
    msg_info "Stopping Service"
    systemctl stop mmdl
    msg_ok "Stopped Service"

    msg_info "Creating Backup"
    cp /opt/mmdl/.env /opt/mmdl.env
    rm -rf /opt/mmdl
    msg_ok "Backup Created"

    fetch_and_deploy_gh_release "mmdl" "intri-in/manage-my-damn-life-nextjs" "tarball"
    NODE_VERSION="22" setup_nodejs

    msg_info "Configuring ${APP}"
    cd /opt/mmdl || exit
    export NEXT_TELEMETRY_DISABLED=1
    $STD npm install
    $STD npm run migrate
    $STD npm run build
    msg_ok "Configured ${APP}"

    msg_info "Starting Service"
    systemctl start mmdl
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
