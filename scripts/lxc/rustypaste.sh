#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: GoldenSpringness
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/orhun/rustypaste

# shellcheck disable=SC2034
APP="rustypaste"
var_tags="${var_tags:-pastebin;storage}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_gh_release "rustypaste" "orhun/rustypaste" "prebuild" "latest" "/opt/rustypaste" "*x86_64-unknown-linux-gnu.tar.gz"
  fetch_and_deploy_gh_release "rustypaste-cli" "orhun/rustypaste-cli" "prebuild" "latest" "/usr/local/bin" "*x86_64-unknown-linux-gnu.tar.gz"

  msg_info "Setting up RustyPaste"
  cd /opt/rustypaste || exit
  sed -i 's|^address = ".*"|address = "0.0.0.0:8000"|' config.toml
  msg_ok "Set up RustyPaste"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/rustypaste.service
[Unit]
Description=rustypaste Service
After=network.target

[Service]
WorkingDirectory=/opt/rustypaste
ExecStart=/opt/rustypaste/rustypaste
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now rustypaste
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/rustypaste/rustypaste ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "rustypaste" "orhun/rustypaste"; then
    msg_info "Stopping Services"
    systemctl stop rustypaste
    msg_ok "Stopped Services"

    create_backup /opt/rustypaste/upload /opt/rustypaste/config.toml

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "rustypaste" "orhun/rustypaste" "prebuild" "latest" "/opt/rustypaste" "*x86_64-unknown-linux-gnu.tar.gz"

    restore_backup

    msg_info "Starting Services"
    systemctl start rustypaste
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi

  if check_for_gh_release "rustypaste-cli" "orhun/rustypaste-cli"; then
    fetch_and_deploy_gh_release "rustypaste-cli" "orhun/rustypaste-cli" "prebuild" "latest" "/usr/local/bin" "*x86_64-unknown-linux-gnu.tar.gz"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
