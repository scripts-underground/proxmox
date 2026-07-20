#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://grafana.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Grafana"
var_tags="${var_tags:-monitoring;visualization}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Setting up Grafana Repository"
  setup_deb822_repo \
    "grafana" \
    "https://apt.grafana.com/gpg.key" \
    "https://apt.grafana.com" \
    "stable" \
    "main"
  msg_ok "Grafana Repository setup successfully"

  msg_info "Installing Grafana"
  $STD apt install -y grafana
  $STD systemctl enable -q --now grafana-server
  msg_ok "Installed Grafana"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! dpkg -s grafana > /dev/null 2>&1; then
    msg_error "No ${APP} Installation Found!"
    exit 233
  fi

  if [[ -f /etc/apt/sources.list.d/grafana.list ]] || [[ ! -f /etc/apt/sources.list.d/grafana.sources ]]; then
    setup_deb822_repo \
      "grafana" \
      "https://apt.grafana.com/gpg.key" \
      "https://apt.grafana.com" \
      "stable" \
      "main"
  fi

  msg_info "Updating ${APP} LXC"
  $STD apt update
  $STD apt --only-upgrade install -y grafana
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
