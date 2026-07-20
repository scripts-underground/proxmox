#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Mips2648
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://jeedom.com/
# shellcheck disable=SC2034
APP="Jeedom"
var_tags="${var_tags:-automation;smarthome}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing dependencies"
  $STD apt install -y \
    lsb-release \
    git
  msg_ok "Dependencies installed"

  msg_warn "WARNING: This script will run an external installer from a third-party source (https://github.com/jeedom/)."
  msg_warn "The following code is NOT maintained or audited by our repository."
  msg_warn "If you have any doubts or concerns, please review the installer code before proceeding:"
  msg_custom "${TAB3}${GATEWAY}${BGN}${CL}" "\e[1;34m" "→  https://raw.githubusercontent.com/jeedom/core/master/install/install.sh"
  echo
  read -r -p "${TAB3}Do you want to continue? [y/N]: " CONFIRM
  if [[ ! "$CONFIRM" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    msg_error "Aborted by user. No changes have been made."
    exit 10
  fi

  DEFAULT_BRANCH="master"
  REPO_URL="https://github.com/jeedom/core.git"

  echo
  while true; do
    read -rp "${TAB3}Enter branch to use (master, beta, alpha...) (Default: ${DEFAULT_BRANCH}): " BRANCH
    BRANCH="${BRANCH:-$DEFAULT_BRANCH}"

    if git ls-remote --heads "$REPO_URL" "refs/heads/$BRANCH" | grep -q .; then
      break
    else
      msg_error "Branch '$BRANCH' does not exist on remote. Please try again."
    fi
  done

  msg_info "Downloading Jeedom installation script"
  cd /tmp || exit
  wget -q https://raw.githubusercontent.com/jeedom/core/"${BRANCH}"/install/install.sh
  chmod +x install.sh
  msg_ok "Installation script downloaded"

  msg_info "Install Jeedom main dependencies, please wait"
  $STD ./install.sh -v "$BRANCH" -s 2
  msg_ok "Installed Jeedom main dependencies"

  msg_info "Install Database"
  $STD ./install.sh -v "$BRANCH" -s 3
  msg_ok "Database installed"

  msg_info "Install Apache"
  $STD ./install.sh -v "$BRANCH" -s 4
  msg_ok "Apache installed"

  msg_info "Install PHP and dependencies"
  $STD ./install.sh -v "$BRANCH" -s 5
  msg_ok "PHP installed"

  msg_info "Download Jeedom core"
  $STD ./install.sh -v "$BRANCH" -s 6
  msg_ok "Download done"

  msg_info "Database customisation"
  $STD ./install.sh -v "$BRANCH" -s 7
  msg_ok "Database customisation done"

  msg_info "Jeedom customisation"
  $STD ./install.sh -v "$BRANCH" -s 8
  msg_ok "Jeedom customisation done"

  msg_info "Configuring Jeedom"
  $STD ./install.sh -v "$BRANCH" -s 9
  msg_ok "Jeedom configured"

  msg_info "Installing Jeedom"
  $STD ./install.sh -v "$BRANCH" -s 10
  msg_ok "Jeedom installed"

  msg_info "Post installation"
  $STD ./install.sh -v "$BRANCH" -s 11
  msg_ok "Post installation done"

  msg_info "Check installation"
  $STD ./install.sh -v "$BRANCH" -s 12
  msg_ok "Installation checked, everything is successfully installed. A reboot is recommended."
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /var/www/html/core/config/version ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating OS"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "OS updated, you can now update Jeedom from the Web UI."
  exit
}
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
