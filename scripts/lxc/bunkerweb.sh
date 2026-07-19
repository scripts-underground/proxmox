#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.bunkerweb.io/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="BunkerWeb"
var_tags="${var_tags:-webserver}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    apt-transport-https \
    lsb-release
  msg_ok "Installed Dependencies"

  RELEASE=$(get_latest_github_release "bunkerity/bunkerweb")
  msg_warn "WARNING: This script will run an external installer from a third-party source (install-bunkerweb.sh)."
  msg_warn "The following code is NOT maintained or audited by our repository."
  msg_warn "If you have any doubts or concerns, please review the installer code before proceeding:"
  msg_custom "${TAB3}${GATEWAY}${BGN}${CL}" "\e[1;34m" "→  https://github.com/bunkerity/bunkerweb/raw/v${RELEASE}/misc/install-bunkerweb.sh"
  echo
  read -r -p "${TAB3}Do you want to continue? [y/N]: " CONFIRM
  if [[ ! "$CONFIRM" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    msg_error "Aborted by user. No changes have been made."
    exit 10
  fi
  msg_info "Installing BunkerWeb (Patience)"
  curl -fsSL -o install-bunkerweb.sh "https://github.com/bunkerity/bunkerweb/raw/v${RELEASE}/misc/install-bunkerweb.sh"
  chmod +x install-bunkerweb.sh
  $STD ./install-bunkerweb.sh --yes
  $STD apt-mark unhold bunkerweb nginx
  cat << EOF > /etc/apt/preferences.d/bunkerweb
Package: bunkerweb
Pin: version ${RELEASE}
Pin-Priority: 1001
EOF
  echo "${RELEASE}" > ~/.bunkerweb
  msg_ok "Installed BunkerWeb"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}/setup${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /etc/bunkerweb ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "bunkerweb" "bunkerity/bunkerweb"; then
    msg_info "Updating BunkerWeb"
    RELEASE=$(get_latest_github_release "bunkerity/bunkerweb")
    cat << EOF > /etc/apt/preferences.d/bunkerweb
Package: bunkerweb
Pin: version ${RELEASE}
Pin-Priority: 1001
EOF
    $STD apt update
    $STD apt-mark unhold bunkerweb nginx
    $STD apt install -y --allow-downgrades bunkerweb="${RELEASE}"
    msg_ok "Updated BunkerWeb"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
