#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: doge0420
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/lyqht/mini-qr

# shellcheck disable=SC2034
APP="Mini-QR"
var_tags="${var_tags:-qr;tools}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y libharfbuzz0b caddy fontconfig
  msg_ok "Installed Dependencies"

  NODE_VERSION="20" setup_nodejs
  fetch_and_deploy_gh_release "mini-qr" "lyqht/mini-qr" "tarball"

  msg_info "Building Mini-QR"
  cd /opt/mini-qr || exit
  $STD npm install
  $STD npm run build
  msg_ok "Built Mini-QR"

  msg_info "Configuring Caddy"
  cat << EOF > /etc/caddy/Caddyfile
:80 {
    root * /opt/mini-qr/dist
    file_server

    # Handle client-side routing
    try_files {path} /index.html

    # Cache static assets
    @assets {
        path /assets/*
    }
    header @assets Cache-Control "public, immutable, max-age=31536000"

    # Correct MIME types for JS modules
    @jsmodules {
        path *.js *.mjs
    }
    header @jsmodules Content-Type "application/javascript"
}
EOF
  systemctl enable -q --now caddy
  systemctl reload caddy
  msg_ok "Configured Caddy"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/mini-qr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "mini-qr" "lyqht/mini-qr"; then
    msg_info "Stopping Service"
    systemctl stop caddy
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "mini-qr" "lyqht/mini-qr" "tarball"

    msg_info "Building Mini-QR"
    cd /opt/mini-qr || exit
    $STD npm install
    $STD npm run build
    msg_ok "Built Mini-QR"

    msg_info "Starting Service"
    systemctl start caddy
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
