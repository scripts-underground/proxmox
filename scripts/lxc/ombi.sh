#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://ombi.io/ | Github: https://github.com/Ombi-app/Ombi

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Ombi"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y libicu-dev
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "ombi" "Ombi-app/Ombi" "prebuild" "latest" "/opt/ombi" "linux-$(get_system_arch).tar.gz"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/ombi.service
[Unit]
Description=Ombi
After=syslog.target network-online.target

[Service]
ExecStart=/opt/ombi/./Ombi
WorkingDirectory=/opt/ombi
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now ombi
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:5000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/ombi ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "ombi" "Ombi-app/Ombi"; then
    msg_info "Stopping Service"
    systemctl stop ombi
    msg_ok "Stopped Service"

    msg_info "Creating backup"
    [[ -f /opt/ombi/Ombi.db ]] && mv /opt/ombi/Ombi.db /opt
    [[ -f /opt/ombi/OmbiExternal.db ]] && mv /opt/ombi/OmbiExternal.db /opt
    [[ -f /opt/ombi/OmbiSettings.db ]] && mv /opt/ombi/OmbiSettings.db /opt
    [[ -f /opt/ombi/database.json ]] && mv /opt/ombi/database.json /opt
    msg_ok "Backup created"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "ombi" "Ombi-app/Ombi" "prebuild" "latest" "/opt/ombi" "linux-$(get_system_arch).tar.gz"
    [[ -f /opt/Ombi.db ]] && mv /opt/Ombi.db /opt/ombi
    [[ -f /opt/OmbiExternal.db ]] && mv /opt/OmbiExternal.db /opt/ombi
    [[ -f /opt/OmbiSettings.db ]] && mv /opt/OmbiSettings.db /opt/ombi
    [[ -f /opt/database.json ]] && mv /opt/database.json /opt/ombi

    msg_info "Starting Service"
    systemctl start ombi
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
