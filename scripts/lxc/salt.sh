#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: bvdberg01
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/saltstack/salt

APP="Salt"
var_tags="${var_tags:-automation;}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-3}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Setting up Salt Repository"
  setup_deb822_repo \
    "salt" \
    "https://packages.broadcom.com/artifactory/api/security/keypair/SaltProjectKey/public" \
    "https://packages.broadcom.com/artifactory/saltproject-deb" \
    "stable"
  $STD apt update
  msg_ok "Setup Salt Repository"

  msg_info "Installing Salt"
  RELEASE=$(get_latest_github_release "saltstack/salt")
  cat << EOF > /etc/apt/preferences.d/salt-pin-1001
Package: salt-*
Pin: version ${RELEASE}
Pin-Priority: 1001
EOF
  $STD apt install -y salt-master
  echo "${RELEASE}" > "$HOME/.salt"
  msg_ok "Installed Salt"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Salt master is listening on the following ports:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}tcp://${IP}:4505${CL} (publisher)"
  echo -e "${TAB}${GATEWAY}${BGN}tcp://${IP}:4506${CL} (request server)"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /etc/salt ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "salt" "saltstack/salt"; then
    RELEASE="$CHECK_UPDATE_RELEASE"
    msg_info "Updating Salt"
    sed -i "s/^\(Pin: version \).*/\1${RELEASE}/" /etc/apt/preferences.d/salt-pin-1001
    $STD apt update
    $STD apt upgrade -y
    echo "${RELEASE}" > "$HOME/.salt"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
