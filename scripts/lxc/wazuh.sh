#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Omar Minaya
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://wazuh.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Wazuh"
var_tags="${var_tags:-security;monitoring}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-25}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  RELEASE=$(curl -fsSL https://api.github.com/repos/wazuh/wazuh/releases/latest | grep '"tag_name"' | awk -F '"' '{print substr($4, 2, length($2)-4)}')

  msg_warn "WARNING: This script will run an external installer from a third-party source (https://wazuh.com/)."
  msg_warn "The following code is NOT maintained or audited by our repository."
  msg_warn "If you have any doubts or concerns, please review the installer code before proceeding:"
  msg_custom "${TAB3}${GATEWAY}${BGN}${CL}" "\e[1;34m" "→  https://packages.wazuh.com/${RELEASE}/wazuh-install.sh "
  echo
  read -r -p "${TAB3}Do you want to continue? [y/N]: " CONFIRM
  if [[ ! "$CONFIRM" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    msg_error "Aborted by user. No changes have been made."
    exit 10
  fi

  msg_info "Setup Wazuh"
  curl -fsSL https://packages.wazuh.com/${RELEASE}/wazuh-install.sh -o wazuh-install.sh
  chmod +x wazuh-install.sh
  if [ "$STD" = "silent" ]; then
    bash wazuh-install.sh -a >> ~/wazuh-install.output
  else
    bash wazuh-install.sh -a | tee -a ~/wazuh-install.output
  fi
  cat ~/wazuh-install.output | grep -E "User|Password" | awk '{$1=$1};1' | sed '1i wazuh-credentials' > ~/wazuh.creds
  rm -f wazuh-*.sh
  rm -f ~/wazuh-install.output
  msg_ok "Setup Wazuh"

  if [ -d /dev/.lxc ]; then
    msg_info "Adding LXC rootcheck exclusion"
    sed -i '/<\/rootcheck>/i \    <ignore>/dev/.lxc</ignore>' /var/ossec/etc/ossec.conf
    msg_ok "Added LXC rootcheck exclusion"
  fi
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:443${CL}"
  echo -e "${INFO}${YW} Show password: cat ~/wazuh.creds${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /lib/systemd/system/wazuh-manager.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating Wazuh LXC"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated Wazuh LXC"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
