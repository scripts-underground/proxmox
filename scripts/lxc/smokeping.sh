#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://oss.oetiker.ch/smokeping/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="SmokePing"
var_tags="${var_tags:-network}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y apache2 apache2-utils
  msg_ok "Installed Dependencies"

  msg_info "Installing SmokePing"
  $STD apt install -y smokeping
  msg_ok "Installed SmokePing"

  msg_info "Configuring SmokePing"
  cat << EOF > /etc/smokeping/config.d/Targets
*** Targets ***

probe = FPing

menu = Top
title = Network Latency Grapher
remark = Welcome to SmokePing

+ Local

menu = Local Targets
title = Local Network

++ Localhost

menu = Localhost
title = Localhost
host = localhost

+ Internet

menu = Internet Targets
title = Internet Connectivity

++ GoogleDNS

menu = Google DNS
title = Google DNS (8.8.8.8)
host = 8.8.8.8

++ CloudflareDNS

menu = Cloudflare DNS
title = Cloudflare DNS (1.1.1.1)
host = 1.1.1.1
EOF
  chmod 644 /etc/smokeping/config.d/Targets
  systemctl enable -q --now apache2
  systemctl restart apache2
  msg_ok "Configured SmokePing"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}/smokeping${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if ! command -v smokeping &> /dev/null; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ${APP}"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated ${APP}"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
