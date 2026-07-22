#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://zwave-js.github.io/zwave-js-ui/#/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Zwave-JS-UI"
var_tags="${var_tags:-smarthome;zwave}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-0}"

function install_script() {
  RELEASE_ARCH="linux"
  [[ "$(uname -m)" == "aarch64" ]] && RELEASE_ARCH="linux-arm64"

  ZWAVE_BIN="zwave-js-ui-linux"
  [[ "$(uname -m)" == "aarch64" ]] && ZWAVE_BIN="zwave-js-ui"

  fetch_and_deploy_gh_release "zwave-js-ui" "zwave-js/zwave-js-ui" "prebuild" "latest" "/opt/zwave-js-ui" "zwave-js-ui-v*-${RELEASE_ARCH}.zip"

  msg_info "Configuring Z-Wave JS UI"
  mkdir -p /opt/zwave_store
  cat << EOF > /opt/.env
ZWAVEJS_EXTERNAL_CONFIG=/opt/zwave_store/.config-db
STORE_DIR=/opt/zwave_store
EOF
  msg_ok "Configured Z-Wave JS UI"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/zwave-js-ui.service
[Unit]
Description=zwave-js-ui
Wants=network-online.target
After=network-online.target

[Service]
User=root
WorkingDirectory=/opt/zwave-js-ui
ExecStart=/opt/zwave-js-ui/${ZWAVE_BIN}
EnvironmentFile=/opt/.env

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now zwave-js-ui
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8091${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/zwave-js-ui ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "zwave-js-ui" "zwave-js/zwave-js-ui"; then
    msg_info "Stopping Service"
    systemctl stop zwave-js-ui
    msg_ok "Stopped Service"

    RELEASE_ARCH="linux"
    [[ "$(uname -m)" == "aarch64" ]] && RELEASE_ARCH="linux-arm64"

    ZWAVE_BIN="zwave-js-ui-linux"
    [[ "$(uname -m)" == "aarch64" ]] && ZWAVE_BIN="zwave-js-ui"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "zwave-js-ui" "zwave-js/zwave-js-ui" "prebuild" "latest" "/opt/zwave-js-ui" "zwave-js-ui-v*-${RELEASE_ARCH}.zip"

    msg_info "Starting Service"
    systemctl start zwave-js-ui
    msg_ok "Started Service"

    msg_info "Cleanup"
    rm -rf /opt/zwave-js-ui/store
    msg_ok "Cleaned"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
