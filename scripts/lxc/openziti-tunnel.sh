#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: emoscardini (emoscardini)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/openziti/ziti

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="OpenZiti-Tunnel"
var_tags="${var_tags:-network;openziti-tunnel}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing OpenZiti"
  install -d -m 0755 /usr/share/keyrings
  curl -sSLf https://get.openziti.io/tun/package-repos.gpg | gpg --dearmor -o /usr/share/keyrings/openziti.gpg
  cat << EOF > /etc/apt/sources.list.d/openziti.sources
Types: deb
URIs: https://packages.openziti.org/zitipax-openziti-deb-stable
Suites: jammy
Components: main
Signed-By: /usr/share/keyrings/openziti.gpg
EOF
  $STD apt update
  $STD apt install -y ziti-edge-tunnel
  sed -i '0,/^ExecStart/ { /^ExecStart/ { n; s|^ExecStart.*|ExecStart=/opt/openziti/bin/ziti-edge-tunnel run-host --verbose=${ZITI_VERBOSE} --identity-dir=${ZITI_IDENTITY_DIR}| } }' /usr/lib/systemd/system/ziti-edge-tunnel.service
  systemctl daemon-reload
  systemctl enable -q ziti-edge-tunnel
  msg_ok "Installed OpenZiti"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} OpenZiti has been installed. To start the tunnel:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN} Place an identity JWT file in /opt/openziti/etc/identities/${CL}"
  echo -e "${TAB}${GATEWAY}${BGN} Then run: systemctl start ziti-edge-tunnel${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/openziti ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating $APP"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated $APP"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
