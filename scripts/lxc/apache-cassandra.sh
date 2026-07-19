#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://cassandra.apache.org/_/index.html

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Apache-Cassandra"
var_tags="${var_tags:-database;NoSQL}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  JAVA_VERSION="11" setup_java

  msg_info "Installing Apache Cassandra"
  setup_deb822_repo \
    "cassandra" \
    "https://downloads.apache.org/cassandra/KEYS" \
    "https://debian.cassandra.apache.org" \
    "41x" \
    "main"
  $STD apt install -y cassandra cassandra-tools
  sed -i -e 's/^rpc_address: localhost/#rpc_address: localhost/g' -e 's/^# rpc_interface: eth1/rpc_interface: eth0/g' /etc/cassandra/cassandra.yaml
  msg_ok "Installed Apache Cassandra"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9042${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/init.d/cassandra ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating Apache Cassandra"
  $STD apt update
  $STD apt install -y --only-upgrade cassandra cassandra-tools
  msg_ok "Updated Apache Cassandra"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
