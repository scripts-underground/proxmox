#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://adguard.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Adguard"
var_tags="${var_tags:-adblock}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_gh_release "AdGuardHome" "AdguardTeam/AdGuardHome" "prebuild" "latest" "/opt/AdGuardHome" "AdGuardHome_linux_$(arch_resolve).tar.gz"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/AdGuardHome.service
[Unit]
Description=AdGuard Home: Network-level blocker
ConditionFileIsExecutable=/opt/AdGuardHome/AdGuardHome
After=syslog.target network-online.target

[Service]
StartLimitInterval=5
StartLimitBurst=10
ExecStart=/opt/AdGuardHome/AdGuardHome "-s" "run"
WorkingDirectory=/opt/AdGuardHome
StandardOutput=file:/var/log/AdGuardHome.out
StandardError=file:/var/log/AdGuardHome.err
Restart=always
RestartSec=10
EnvironmentFile=-/etc/sysconfig/AdGuardHome

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now AdGuardHome
  msg_ok "Created Service"
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

  if [[ ! -d /opt/AdGuardHome ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_error "Adguard Home can only be updated via the user interface."
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
