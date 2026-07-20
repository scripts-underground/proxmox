#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.drawio.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="DrawIO"
var_tags="${var_tags:-diagrams}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y tomcat11
  msg_ok "Installed Dependencies"

  USE_ORIGINAL_FILENAME=true fetch_and_deploy_gh_release "drawio" "jgraph/drawio" "singlefile" "latest" "/var/lib/tomcat11/webapps" "draw.war"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8080/draw${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /var/lib/tomcat11/webapps/draw.war ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "drawio" "jgraph/drawio"; then
    msg_info "Stopping service"
    systemctl stop tomcat11
    msg_ok "Service stopped"

    msg_info "Updating Debian LXC"
    $STD apt update
    $STD apt upgrade -y
    msg_ok "Updated Debian LXC"

    USE_ORIGINAL_FILENAME=true fetch_and_deploy_gh_release "drawio" "jgraph/drawio" "singlefile" "latest" "/var/lib/tomcat11/webapps" "draw.war"

    msg_info "Starting service"
    systemctl start tomcat11
    msg_ok "Service started"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
