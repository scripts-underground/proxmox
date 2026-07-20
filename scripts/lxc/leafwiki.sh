#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/perber/leafwiki

APP="LeafWiki"
var_tags="${var_tags:-wiki;markdown;notes}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_gh_release "leafwiki" "perber/leafwiki" "singlefile" "latest" "/usr/local/bin" "leafwiki-v*-linux-$(get_system_arch)"

  msg_info "Configuring LeafWiki"
  mkdir -p /opt/leafwiki/data
  mkdir -p /etc/leafwiki
  JWT_SECRET=$(openssl rand -hex 32)
  ADMIN_PASS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c12)
  cat << EOF > /etc/leafwiki/.env
LEAFWIKI_DATA_DIR=/opt/leafwiki/data
LEAFWIKI_HOST=0.0.0.0
LEAFWIKI_PORT=8080
LEAFWIKI_JWT_SECRET=${JWT_SECRET}
LEAFWIKI_ADMIN_PASSWORD=${ADMIN_PASS}
LEAFWIKI_ALLOW_INSECURE=true
EOF
  msg_ok "Configured LeafWiki"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/leafwiki.service
[Unit]
Description=LeafWiki
After=network.target

[Service]
Type=simple
User=root
EnvironmentFile=/etc/leafwiki/.env
ExecStart=/usr/local/bin/leafwiki
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now leafwiki
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /usr/local/bin/leafwiki ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "leafwiki" "perber/leafwiki"; then
    msg_info "Stopping Service"
    systemctl stop leafwiki
    msg_ok "Stopped Service"

    create_backup /opt/leafwiki/data
    fetch_and_deploy_gh_release "leafwiki" "perber/leafwiki" "singlefile" "latest" "/usr/local/bin" "leafwiki-v*-linux-$(get_system_arch)"
    restore_backup

    msg_info "Starting Service"
    systemctl start leafwiki
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
