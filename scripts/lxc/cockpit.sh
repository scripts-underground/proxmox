#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster) | Co-Author: havardthom
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/cockpit-project/cockpit

# shellcheck disable=SC2034
APP="Cockpit"
var_tags="${var_tags:-monitoring;network}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Cockpit"
  source /etc/os-release
  cat << EOF > /etc/apt/sources.list.d/debian-backports.sources
Types: deb deb-src
URIs: http://deb.debian.org/debian
Suites: ${VERSION_CODENAME}-backports
Components: main
Enabled: yes
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

  $STD apt update
  $STD apt install -t "${VERSION_CODENAME}-backports" cockpit cracklib-runtime --no-install-recommends -y
  sed -i "s/root//g" /etc/cockpit/disallowed-users
  msg_ok "Installed Cockpit"

  # 45Drives only publishes amd64 packages
  if [[ "$(get_system_arch)" != "arm64" ]] && [[ "$(get_system_arch)" != "aarch64" ]]; then
    read -r -p "${TAB3}Would you like to install 45Drives' cockpit-file-sharing, cockpit-identities, and cockpit-navigator? <y/N> " prompt
    if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
      install_45drives=true
      if [[ "${VERSION_ID}" -ge 13 ]]; then
        read -r -p "${TAB3}Debian ${VERSION_ID} is not officially supported by 45Drives yet, would you like to continue anyway? <y/N> " prompt
        if [[ ! "${prompt,,}" =~ ^(y|yes)$ ]]; then
          install_45drives=false
        fi
      fi
      if [[ "$install_45drives" == "true" ]]; then
        msg_info "Installing 45Drives' cockpit extensions"
        setup_deb822_repo "45drives" \
          "https://repo.45drives.com/key/gpg.asc" \
          "https://repo.45drives.com/enterprise/debian" \
          "bookworm" \
          "main" \
          "amd64"
        $STD apt install -y cockpit-file-sharing cockpit-identities cockpit-navigator
        msg_ok "Installed 45Drives' cockpit extensions"
      fi
    fi
  fi
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9090${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /etc/cockpit ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP} LXC"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated ${APP} LXC"
  msg_ok "Updated successfully!"
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
