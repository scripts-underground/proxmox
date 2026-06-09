#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
source <(curl -fsSL "$REPO_BASE/misc/build.func")

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/kiwix/kiwix-tools

APP="Kiwix"
var_tags="${var_tags:-documentation;offline}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_unprivileged="${var_unprivileged:-1}"

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! dpkg -s kiwix-tools &>/dev/null; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  CURRENT=$(cat /root/.kiwix 2>/dev/null || dpkg -s kiwix-tools 2>/dev/null | awk '/^Version:/{print $2}')

  msg_info "Stopping Service"
  systemctl stop kiwix-serve
  msg_ok "Stopped Service"

  msg_info "Updating Kiwix-Tools"
  $STD apt update
  $STD apt install -y --only-upgrade kiwix-tools
  RELEASE=$(dpkg -s kiwix-tools 2>/dev/null | awk '/^Version:/{print $2}')
  echo "${RELEASE}" >/root/.kiwix
  msg_ok "Updated Kiwix-Tools"

  if [[ "$CURRENT" == "$RELEASE" ]]; then
    msg_ok "Already on latest version: ${CURRENT}"
  else
    msg_ok "Updated successfully from ${CURRENT} to ${RELEASE}!"
  fi

  msg_info "Starting Service"
  systemctl start kiwix-serve
  msg_ok "Started Service"
  exit
}

function install_script() {
  color
  verb_ip6
  catch_errors
  setting_up_container
  network_check
  update_os

  msg_info "Installing Dependencies"
  $STD apt install -y software-properties-common
  msg_ok "Installed Dependencies"

  msg_info "Adding Kiwix PPA"
  add-apt-repository -y ppa:kiwixteam/release >>"$(get_active_logfile)" 2>&1
  $STD apt update
  msg_ok "Added Kiwix PPA"

  msg_info "Installing Kiwix-Tools"
  $STD apt install -y kiwix-tools
  RELEASE=$(dpkg -s kiwix-tools 2>/dev/null | awk '/^Version:/{print $2}')
  echo "${RELEASE}" >/root/.kiwix
  msg_ok "Installed Kiwix-Tools ${RELEASE}"

  mkdir -p /data

  msg_info "Creating Service"
  cat <<'EOF' >/etc/systemd/system/kiwix-serve.service
[Unit]
Description=Kiwix ZIM Server
After=network.target

[Service]
Type=simple
ExecStart=/bin/sh -c 'exec /usr/bin/kiwix-serve --port 8080 /data/*.zim'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q kiwix-serve
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Place ZIM files in /data, then:${CL}"
  echo -e "${TAB}systemctl start kiwix-serve${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
