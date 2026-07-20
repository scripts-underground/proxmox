#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# Co-Author: remz1337
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/lldap/lldap

# shellcheck disable=SC2034
APP="lldap"
var_tags="${var_tags:-ldap}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing lldap"
  source /etc/os-release
  os=$ID
  if [ "$os" == "ubuntu" ]; then
    DISTRO="xUbuntu"
  else
    DISTRO="${os^}"
  fi
  curl -fsSL "https://download.opensuse.org/repositories/home:Masgalor:LLDAP/${DISTRO}_${VERSION_ID}/Release.key" | gpg --dearmor > /usr/share/keyrings/home_Masgalor_LLDAP.gpg
  cat << EOF > /etc/apt/sources.list.d/home:Masgalor:LLDAP.sources
Types: deb
URIs: http://download.opensuse.org/repositories/home:/Masgalor:/LLDAP/${DISTRO}_${VERSION_ID}/
Suites: /
Signed-By: /usr/share/keyrings/home_Masgalor_LLDAP.gpg
EOF
  $STD apt update
  $STD apt install -y lldap
  systemctl enable -q --now lldap
  msg_ok "Installed lldap"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:17170${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /lib/systemd/system/lldap.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating lldap"
  $STD apt update
  $STD apt upgrade -y lldap
  msg_ok "Updated lldap"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
