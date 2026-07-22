#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://zoraxy.aroz.org/ | Github: https://github.com/tobychui/zoraxy

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Zoraxy"
var_tags="${var_tags:-network}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_gh_release "zoraxy" "tobychui/zoraxy" "singlefile" "latest" "/opt/zoraxy" "zoraxy_linux_$(get_system_arch)"

  msg_info "Configuring Zoraxy"
  ln -s /opt/zoraxy/zoraxy /usr/local/bin/zoraxy
  msg_ok "Configured Zoraxy"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/zoraxy.service
[Unit]
Description=General purpose request proxy and forwarding tool
After=syslog.target network-online.target

[Service]
ExecStart=/opt/zoraxy/./zoraxy
WorkingDirectory=/opt/zoraxy/
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now zoraxy
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/zoraxy/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "zoraxy" "tobychui/zoraxy"; then
    msg_info "Stopping service"
    systemctl stop zoraxy
    msg_ok "Service stopped"

    fetch_and_deploy_gh_release "zoraxy" "tobychui/zoraxy" "singlefile" "latest" "/opt/zoraxy" "zoraxy_linux_$(get_system_arch)"

    msg_info "Starting service"
    systemctl start zoraxy
    msg_ok "Service started"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
