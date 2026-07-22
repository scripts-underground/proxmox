#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/versity/versitygw

# shellcheck disable=SC2034
APP="VersityGW"
var_tags="${var_tags:-s3;storage;gateway}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y openssl
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "versitygw" "versity/versitygw" "binary"

  msg_info "Configuring VersityGW"
  ACCESS_KEY=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-20)
  SECRET_KEY=$(openssl rand -base64 36 | tr -dc 'a-zA-Z0-9' | cut -c1-40)
  cat << EOF > /etc/versitygw.d/gateway.conf
VGW_BACKEND=posix
VGW_BACKEND_ARG=/opt/versitygw-data
VGW_PORT=:7070
ROOT_ACCESS_KEY_ID=${ACCESS_KEY}
ROOT_SECRET_ACCESS_KEY=${SECRET_KEY}
VGW_WEBUI_PORT=:7071
VGW_WEBUI_NO_TLS=true
EOF
  msg_ok "Configured VersityGW"

  msg_info "Enabling Service"
  systemctl enable -q --now versitygw@gateway
  msg_ok "Enabled Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:7070 (S3 Gateway) | http://${IP}:7071 (WebUI)${CL}"
  echo -e "${INFO}${YW}Credentials stored in /etc/versitygw.d/gateway.conf${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /usr/bin/versitygw ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "versitygw" "versity/versitygw"; then
    msg_info "Stopping Service"
    systemctl stop versitygw@gateway
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "versitygw" "versity/versitygw" "binary"

    msg_info "Starting Service"
    systemctl start versitygw@gateway
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
