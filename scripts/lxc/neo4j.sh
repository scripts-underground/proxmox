#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster) | Co-Author: havardthom
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://neo4j.com/product/neo4j-graph-database/

# shellcheck disable=SC2034
APP="Neo4j"
var_tags="${var_tags:-database}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  JAVA_VERSION="21" setup_java

  msg_info "Installing Neo4j (patience)"
  curl -fsSL "https://debian.neo4j.com/neotechnology.gpg.key" | gpg --dearmor -o /etc/apt/keyrings/neotechnology.gpg
  echo 'deb [signed-by=/etc/apt/keyrings/neotechnology.gpg] https://debian.neo4j.com stable latest' > /etc/apt/sources.list.d/neo4j.list
  $STD apt update
  $STD apt install -y neo4j
  sed -i '/server.default_listen_address/s/^#//' /etc/neo4j/neo4j.conf
  systemctl enable -q --now neo4j
  msg_ok "Installed Neo4j"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:7474${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /etc/neo4j ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  JAVA_VERSION="21" setup_java

  msg_info "Updating ${APP}"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
