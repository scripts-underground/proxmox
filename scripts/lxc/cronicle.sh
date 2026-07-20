#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://cronicle.net/

# shellcheck disable=SC2034
APP="Cronicle"
var_tags="${var_tags:-task-scheduler}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  NODE_VERSION="22" setup_nodejs
  fetch_and_deploy_gh_release "cronicle" "jhuckaby/Cronicle" "tarball"

  msg_info "Configuring Cronicle Primary Server"
  cd /opt/cronicle || exit
  $STD npm install
  $STD node bin/build.js dist
  sed -i "s/localhost:3012/${LOCAL_IP}:3012/g" /opt/cronicle/conf/config.json
  $STD /opt/cronicle/bin/control.sh setup
  $STD /opt/cronicle/bin/control.sh start
  msg_ok "Configured Cronicle Primary Server"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3012${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  UPD=$(msg_menu "Cronicle Update Options" \
    "1" "Update ${APP}" \
    "2" "Install ${APP} Worker")

  if [ "$UPD" == "1" ]; then
    if [[ ! -d /opt/cronicle ]]; then
      msg_error "No ${APP} Installation Found!"
      exit
    fi
    NODE_VERSION="22" setup_nodejs

    msg_info "Updating Cronicle"
    $STD /opt/cronicle/bin/control.sh upgrade
    msg_ok "Updated Cronicle"
    exit
  fi
  if [ "$UPD" == "2" ]; then
    NODE_VERSION="22" setup_nodejs
    if check_for_gh_release "cronicle" "jhuckaby/Cronicle"; then
      msg_info "Installing Dependencies"
      ensure_dependencies git build-essential ca-certificates
      msg_ok "Installed Dependencies"

      NODE_VERSION="22" setup_nodejs
      fetch_and_deploy_gh_release "cronicle" "jhuckaby/Cronicle" "tarball"

      msg_info "Configuring Cronicle Worker"
      cd /opt/cronicle || exit
      $STD npm install
      $STD node bin/build.js dist
      sed -i "s/localhost:3012/${LOCAL_IP}:3012/g" /opt/cronicle/conf/config.json
      $STD /opt/cronicle/bin/control.sh start
      msg_ok "Installed Cronicle Worker"
      echo -e "\n Add Masters secret key to /opt/cronicle/conf/config.json \n"
      msg_ok "Updated successfully!"
      exit
    fi
  fi
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
