#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Forceu/Gokapi

# shellcheck disable=SC2034
APP="Gokapi"
var_tags="${var_tags:-file;sharing}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_gh_release "gokapi" "Forceu/Gokapi" "prebuild" "latest" "/opt/gokapi" "*linux*$(get_system_arch).zip"

  msg_info "Configuring Gokapi"
  mkdir -p /opt/gokapi/{data,config}
  chmod +x /opt/gokapi/gokapi
  msg_ok "Configured Gokapi"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/gokapi.service
[Unit]
Description=gokapi

[Service]
Type=simple
Environment=GOKAPI_DATA_DIR=/opt/gokapi/data
Environment=GOKAPI_CONFIG_DIR=/opt/gokapi/config
ExecStart=/opt/gokapi/gokapi

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now gokapi
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:53842/setup${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/gokapi ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "gokapi" "Forceu/Gokapi"; then
    msg_info "Stopping Service"
    systemctl stop gokapi
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "gokapi" "Forceu/Gokapi" "prebuild" "latest" "/opt/gokapi" "*linux*$(get_system_arch).zip"

    if [[ -f /opt/gokapi/gokapi-linux_amd64 ]]; then
      rm -f /opt/gokapi/gokapi-linux_amd64
    fi
    if grep -q "gokapi-linux_amd64" /etc/systemd/system/gokapi.service 2> /dev/null; then
      sed -i 's|gokapi-linux_amd64|gokapi|g' /etc/systemd/system/gokapi.service
      systemctl daemon-reload
    fi

    msg_info "Starting Service"
    systemctl start gokapi
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
