#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.hivemq.com/ | Github: https://github.com/hivemq/hivemq-community-edition

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="HiveMQ"
var_tags="${var_tags:-mqtt}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y rsync
  msg_ok "Installed Dependencies"

  msg_info "Setting up Java"
  JAVA_VERSION="21" setup_java
  msg_ok "Set up Java"

  fetch_and_deploy_gh_release "hivemq" "hivemq/hivemq-community-edition" "prebuild" "latest" "/opt/hivemq" "hivemq-ce-*.zip"

  msg_info "Configuring HiveMQ CE"
  useradd -d /opt/hivemq hivemq
  chown -R hivemq:hivemq /opt/hivemq
  chmod +x /opt/hivemq/bin/run.sh
  cp /opt/hivemq/bin/init-script/hivemq.service /etc/systemd/system/hivemq.service
  rm /opt/hivemq/conf/config.xml
  mv /opt/hivemq/conf/examples/configuration/config-sample-tcp-and-websockets.xml /opt/hivemq/conf/config.xml
  msg_ok "Configured HiveMQ CE"

  msg_info "Starting Service"
  systemctl enable -q --now hivemq
  msg_ok "Service started"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:1883${CL}"
  echo -e "${INFO}${YW}Config file: ${GN}/opt/hivemq/conf/config.xml${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/hivemq ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  JAVA_VERSION="21" setup_java
  if check_for_gh_release "hivemq" "hivemq/hivemq-community-edition"; then
    msg_info "Stopping Service"
    systemctl stop hivemq
    msg_ok "Stopped Service"

    ensure_dependencies rsync
    create_backup /opt/hivemq/conf

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "hivemq" "hivemq/hivemq-community-edition" "prebuild" "latest" "/opt/hivemq" "hivemq-ce-*.zip"

    restore_backup

    msg_info "Starting Service"
    systemctl start hivemq
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
