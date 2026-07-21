#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/NodeBB/NodeBB

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="NodeBB"
var_tags="${var_tags:-forum}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies (Patience)"
  $STD apt install -y \
    build-essential \
    redis-server \
    expect \
    ca-certificates
  msg_ok "Installed Dependencies"

  setup_mongodb
  NODE_VERSION="22" setup_nodejs

  msg_info "Configuring MongoDB"
  MONGO_ADMIN_USER="admin"
  MONGO_ADMIN_PWD="$(openssl rand -base64 18 | cut -c1-13)"
  NODEBB_USER="nodebb"
  NODEBB_PWD="$(openssl rand -base64 18 | cut -c1-13)"
  MONGO_CONNECTION_STRING="mongodb://${NODEBB_USER}:${NODEBB_PWD}@localhost:27017/nodebb"
  NODEBB_SECRET="$(uuidgen)"
  cat << EOF > ~/nodebb.creds
NodeBB-Credentials
Mongo Database User: $MONGO_ADMIN_USER
Mongo Database Password: $MONGO_ADMIN_PWD
NodeBB User: $NODEBB_USER
NodeBB Password: $NODEBB_PWD
NodeBB Secret: $NODEBB_SECRET
EOF

  $STD mongosh << EOF
use admin
db.createUser({
  user: "$MONGO_ADMIN_USER",
  pwd: "$MONGO_ADMIN_PWD",
  roles: [{ role: "root", db: "admin" }]
})

use nodebb
db.createUser({
  user: "$NODEBB_USER",
  pwd: "$NODEBB_PWD",
  roles: [
    { role: "readWrite", db: "nodebb" },
    { role: "clusterMonitor", db: "admin" }
  ]
})
quit()
EOF
  sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongod.conf
  sed -i '/security:/d' /etc/mongod.conf
  bash -c 'echo -e "\nsecurity:\n  authorization: enabled" >> /etc/mongod.conf'
  systemctl restart mongod
  msg_ok "MongoDB configured"

  fetch_and_deploy_gh_release "nodebb" "NodeBB/NodeBB" "tarball"

  msg_info "Configuring NodeBB"
  cd /opt/nodebb || exit
  touch pidfile
  expect << EOF > /dev/null 2>&1
log_file /dev/null
set timeout -1

spawn ./nodebb setup
expect "URL used to access this NodeBB" {
    send "http://localhost:4567\r"
}
expect "Please enter a NodeBB secret" {
    send "$NODEBB_SECRET\r"
}
expect "Would you like to submit anonymous plugin usage to nbbpm? (yes)" {
    send "no\r"
}
expect "Which database to use (mongo)" {
    send "mongo\r"
}
expect "Format: mongodb://*" {
    send "$MONGO_CONNECTION_STRING\r"
}
expect "Administrator username" {
    send "community-scripts\r"
}
expect "Administrator email address" {
    send "admin@community-scripts.org\r"
}
expect "Password" {
    send "community-scripts\r"
}
expect "Confirm Password" {
    send "community-scripts\r"
}
expect eof
EOF
  msg_ok "Configured NodeBB"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/nodebb.service
[Unit]
Description=NodeBB
Documentation=https://docs.nodebb.org
After=system.slice multi-user.target mongod.service

[Service]
Type=forking
User=root

WorkingDirectory=/opt/nodebb
PIDFile=/opt/nodebb/pidfile
ExecStart=/usr/bin/node /opt/nodebb/loader.js
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now nodebb
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:4567${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/nodebb ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "nodebb" "NodeBB/NodeBB"; then
    msg_info "Stopping Service"
    systemctl stop nodebb
    msg_ok "Stopped Service"

    msg_info "Updating ${APP}"
    cd /opt/nodebb || exit
    $STD ./nodebb upgrade
    echo "${CHECK_UPDATE_RELEASE}" > ~/.nodebb
    msg_ok "Updated ${APP}"

    msg_info "Starting Service"
    systemctl start nodebb
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
