#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Michel Roegl-Brunner (michelroegl-brunner)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://checkmk.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="checkmk"
var_tags="${var_tags:-monitoring}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  ensure_dependencies gpg
  msg_ok "Installed Dependencies"

  local RELEASE
  RELEASE=$(curl_with_retry "https://api.github.com/repos/checkmk/checkmk/tags" "-" | grep "name" | awk '{print substr($2, 3, length($2)-4) }' | tr ' ' '\n' | grep -Ev 'rc|b' | sort -V | tail -n 1)
  RELEASE="${RELEASE%%+*}"

  msg_info "Installing Checkmk ${RELEASE}"
  curl_download "/opt/checkmk.deb" "https://download.checkmk.com/checkmk/${RELEASE}/check-mk-community-${RELEASE}_0.$(get_os_info codename)_amd64.deb"
  $STD apt install -y /opt/checkmk.deb
  rm -rf /opt/checkmk.deb
  msg_ok "Installed Checkmk"

  msg_info "Creating Monitoring Site"
  $STD omd create monitoring
  $STD omd start monitoring
  msg_ok "Created Monitoring Site"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}/monitoring${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! command -v omd &> /dev/null; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  local RELEASE
  RELEASE=$(curl_with_retry "https://api.github.com/repos/checkmk/checkmk/tags" "-" | grep "name" | awk '{print substr($2, 3, length($2)-4) }' | tr ' ' '\n' | grep -Ev 'rc|b' | sort -V | tail -n 1)
  RELEASE="${RELEASE%%+*}"

  msg_info "Updating Checkmk"
  $STD omd stop monitoring
  $STD omd -f rm monitoringbackup 2> /dev/null || true
  $STD omd cp monitoring monitoringbackup
  curl_download "/opt/checkmk.deb" "https://download.checkmk.com/checkmk/${RELEASE}/check-mk-community-${RELEASE}_0.$(get_os_info codename)_amd64.deb"
  $STD apt install -y /opt/checkmk.deb

  local OMD_VERSION
  OMD_VERSION=$(omd versions 2> /dev/null | grep "^${RELEASE}" | awk '{print $1}')
  if [[ -z "${OMD_VERSION}" ]]; then
    msg_error "Could not find installed OMD version for release ${RELEASE}"
    exit 1
  fi

  $STD omd --force -V "${OMD_VERSION}" update --conflict=install monitoring
  $STD omd start monitoring
  $STD omd -f rm monitoringbackup
  $STD omd cleanup
  rm -rf /opt/checkmk.deb
  msg_ok "Updated Checkmk"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
