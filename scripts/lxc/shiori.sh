#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/go-shiori/shiori

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Shiori"
var_tags="${var_tags:-bookmarks;read-it-later;notes}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_git_repo="${var_lxc_git_repo:-go-shiori/shiori}"

function install_script() {
  msg_info "Fetching Shiori"
  fetch_and_deploy_gh_release "shiori" "$var_lxc_git_repo" "prebuild" "latest" "/opt/shiori" "shiori_Linux_$(get_system_arch)_*.tar.gz"
  chmod +x /opt/shiori/shiori
  msg_ok "Fetched Shiori"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/shiori.service
[Unit]
Description=Shiori Bookmark Manager
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/shiori
Environment=HOME=/opt/shiori
ExecStart=/opt/shiori/shiori serve -p 80
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now shiori
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  render_header
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/shiori ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "shiori" "$var_lxc_git_repo"; then
    msg_info "Stopping Service"
    systemctl stop shiori
    msg_ok "Stopped Service"

    if [[ -d /opt/shiori/data ]]; then
      cp -rp /opt/shiori/data /tmp/shiori_data
    fi
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "shiori" "$var_lxc_git_repo" "prebuild" "latest" "/opt/shiori" "shiori_Linux_$(get_system_arch)_*.tar.gz"
    chmod +x /opt/shiori/shiori
    if [[ -d /tmp/shiori_data ]]; then
      cp -rp /tmp/shiori_data /opt/shiori/data
      rm -rf /tmp/shiori_data
    fi

    msg_info "Starting Service"
    systemctl start shiori
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
