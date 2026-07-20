#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://gitlab.com/fmd-foss/fmd-server

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="FMD-Server"
var_tags="${var_tags:-FMD}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_gl_release "fmd-server" "fmd-foss/fmd-server" "prebuild" "latest" "/opt/fmd-server" "fmd-server-*.zip"
  create_self_signed_cert "fmd-server"

  msg_info "Configuring fmd-server"
  cd /opt/fmd-server || exit
  chmod +x fmd-server-*
  cp config.example.yml config.yml
  edit_yaml_config config.yml "WebDir" '"/opt/fmd-server/web/dist/"'
  edit_yaml_config config.yml "DatabaseDir" '"/opt/fmd-server/db/"'
  edit_yaml_config config.yml "ServerCrt" '"/etc/ssl/fmd-server/fmd-server.crt"'
  edit_yaml_config config.yml "ServerKey" '"/etc/ssl/fmd-server/fmd-server.key"'
  msg_ok "Configured fmd-server"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/fmd-server.service
[Unit]
Description=fmd-server Service
After=network.target

[Service]
WorkingDirectory=/opt/fmd-server
ExecStart=/opt/fmd-server/fmd-server-$(get_system_arch) serve
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  $STD systemctl enable -q --now fmd-server
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:8443${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/fmd-server ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gl_release "fmd-server" "fmd-foss/fmd-server"; then
    msg_info "Stopping Service"
    systemctl stop fmd-server
    msg_ok "Stopped Service"

    create_backup /opt/fmd-server/config.yml /opt/fmd-server/db

    CLEAN_INSTALL=1 fetch_and_deploy_gl_release "fmd-server" "fmd-foss/fmd-server" "prebuild" "latest" "/opt/fmd-server" "fmd-server-*.zip"

    msg_info "Configuring FMD-Server"
    cd /opt/fmd-server || exit
    chmod +x fmd-server-*
    msg_ok "Configured FMD-Server"

    restore_backup

    msg_info "Starting Service"
    systemctl start fmd-server
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
