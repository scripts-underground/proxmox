#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: kristocopani
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.inspircd.org/

APP="InspIRCd"
var_tags="${var_tags:-IRC}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_gh_release "inspircd" "inspircd/inspircd" "binary" "latest" "" "inspircd_*.deb13u1_$(get_system_arch).deb"

  msg_info "Configuring InspIRCd"
  cat << EOF > /etc/inspircd/inspircd.conf
<define name="networkDomain" value="community-scripts.org">
<define name="networkName" value="Proxmox VE Helper-Scripts">

<server
        name="irc.&networkDomain;"
        description="&networkName; IRC server"
        network="&networkName;">
<admin
       name="Admin"
       description="Supreme Overlord"
       email="irc@&networkDomain;">
<bind address="" port="6667" type="clients">
EOF
  systemctl enable -q --now inspircd
  msg_ok "Installed InspIRCd"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:6667${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /lib/systemd/system/inspircd.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "inspircd" "inspircd/inspircd"; then
    msg_info "Stopping Service"
    systemctl stop inspircd
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "inspircd" "inspircd/inspircd" "binary" "latest" "" "inspircd_*.deb13u1_$(get_system_arch).deb"

    msg_info "Starting Service"
    systemctl start inspircd
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
