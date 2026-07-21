#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://rustdesk.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="RustDesk Server"
var_tags="${var_tags:-remote-desktop}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_gh_release "rustdesk-hbbr" "lejianwen/rustdesk-server" "binary" "latest" "" "rustdesk-server-hbbr*$(get_system_arch).deb"
  fetch_and_deploy_gh_release "rustdesk-hbbs" "lejianwen/rustdesk-server" "binary" "latest" "" "rustdesk-server-hbbs*$(get_system_arch).deb"
  fetch_and_deploy_gh_release "rustdesk-utils" "lejianwen/rustdesk-server" "binary" "latest" "" "rustdesk-server-utils*$(get_system_arch).deb"
  fetch_and_deploy_gh_release "rustdesk-api" "lejianwen/rustdesk-api" "binary" "latest" "" "rustdesk-api-server*$(get_system_arch).deb"
  msg_info "Enabling Services"
  systemctl enable -q --now rustdesk-hbbr
  systemctl enable -q --now rustdesk-hbbs
  systemctl enable -q --now rustdesk-api
  msg_ok "Enabled Services"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:21114${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -x /usr/bin/hbbr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "rustdesk-hbbs" "lejianwen/rustdesk-server"; then
    msg_info "Stopping Services"
    systemctl stop rustdesk-hbbr rustdesk-hbbs
    [[ -f /lib/systemd/system/rustdesk-api.service ]] && systemctl stop rustdesk-api
    msg_ok "Stopped Services"

    fetch_and_deploy_gh_release "rustdesk-hbbr" "lejianwen/rustdesk-server" "binary" "latest" "" "rustdesk-server-hbbr*$(get_system_arch).deb"
    fetch_and_deploy_gh_release "rustdesk-hbbs" "lejianwen/rustdesk-server" "binary" "latest" "" "rustdesk-server-hbbs*$(get_system_arch).deb"
    fetch_and_deploy_gh_release "rustdesk-utils" "lejianwen/rustdesk-server" "binary" "latest" "" "rustdesk-server-utils*$(get_system_arch).deb"
    fetch_and_deploy_gh_release "rustdesk-api" "lejianwen/rustdesk-api" "binary" "latest" "" "rustdesk-api-server*$(get_system_arch).deb"

    msg_info "Starting Services"
    systemctl start -q rustdesk-*
    msg_ok "Started Services"

    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
