#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://jitsi.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Jitsi-Meet"
var_tags="${var_tags:-video;conference;communication}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-12}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y nginx
  msg_ok "Installed Dependencies"

  source /etc/os-release
  setup_deb822_repo "jitsi" \
    "https://download.jitsi.org/jitsi-key.gpg.key" \
    "https://download.jitsi.org" \
    "stable/" \
    ""

  msg_info "Installing Jitsi Meet"
  echo "jitsi-videobridge2 jitsi-videobridge/jvb-hostname string ${LOCAL_IP}" | debconf-set-selections
  echo "jitsi-meet-web-config jitsi-meet/cert-choice select Generate a new self-signed certificate" | debconf-set-selections
  DEBIAN_FRONTEND=noninteractive $STD apt install -y jitsi-meet
  msg_ok "Installed Jitsi Meet"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}https://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /etc/jitsi ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating Jitsi Meet"
  $STD apt update
  $STD apt install -y --only-upgrade \
    jitsi-meet \
    jicofo \
    jitsi-videobridge2 \
    prosody
  msg_ok "Updated Jitsi Meet"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
