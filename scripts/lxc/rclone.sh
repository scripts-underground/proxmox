#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://rclone.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Rclone"
var_tags="${var_tags:-os;storage}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_fuse="${var_fuse:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y apache2-utils fuse3
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "rclone" "rclone/rclone" "prebuild" "latest" "/opt/rclone" "rclone*linux-$(get_system_arch).zip"

  msg_info "Installing rclone"
  cd /opt/rclone || exit
  RCLONE_PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  $STD htpasswd -cb -B /opt/login.pwd admin "$RCLONE_PASSWORD"
  cat << EOF > ~/rclone.creds
rclone-Credentials
rclone User Name: admin
rclone Password: $RCLONE_PASSWORD
EOF
  msg_ok "Installed rclone"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/rclone-web.service
[Unit]
Description=Rclone Web GUI
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/rclone
ExecStart=/opt/rclone/rclone rcd --rc-web-gui --rc-web-gui-no-open-browser --rc-addr :3000 --rc-htpasswd /opt/login.pwd
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now rclone-web
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/rclone ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "rclone" "rclone/rclone"; then
    msg_info "Stopping Service"
    systemctl stop rclone-web
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "rclone" "rclone/rclone" "prebuild" "latest" "/opt/rclone" "rclone*linux-$(get_system_arch).zip"

    msg_info "Starting Service"
    systemctl start rclone-web
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
