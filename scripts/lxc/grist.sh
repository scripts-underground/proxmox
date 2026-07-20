#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: cfurrow
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/gristlabs/grist-core
# Co-Author: Slaviša Arežina (tremor021)

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Grist"
var_tags="${var_tags:-database;spreadsheet}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-3072}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    make \
    ca-certificates \
    python3-venv \
    git
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" NODE_MODULE="yarn@latest" setup_nodejs

  fetch_and_deploy_gh_release "grist" "gristlabs/grist-core" "tarball"

  msg_info "Installing Grist"
  export CYPRESS_INSTALL_BINARY=0
  export NODE_OPTIONS="--max-old-space-size=2048"
  cd /opt/grist || exit
  $STD yarn install
  $STD yarn run build:prod
  $STD yarn run install:python
  cat << EOF > /opt/grist/.env
NODE_ENV=production
GRIST_HOST=0.0.0.0
EOF
  msg_ok "Installed Grist"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/grist.service
[Unit]
Description=Grist
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/grist
ExecStart=/usr/bin/yarn run start:prod
EnvironmentFile=-/opt/grist/.env

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now grist
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8484${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/grist ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="22" NODE_MODULE="yarn@latest" setup_nodejs
  ensure_dependencies git

  if check_for_gh_release "grist" "gristlabs/grist-core"; then
    msg_info "Stopping Service"
    systemctl stop grist
    msg_ok "Stopped Service"

    create_backup /opt/grist/.env /opt/grist/grist-sessions.db /opt/grist/landing.db

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "grist" "gristlabs/grist-core" "tarball"

    restore_backup

    msg_info "Updating Grist"
    mkdir -p /opt/grist/docs
    cd /opt/grist || exit
    $STD yarn install
    $STD yarn run build:prod
    $STD yarn run install:python
    msg_ok "Updated Grist"

    msg_info "Starting Service"
    systemctl start grist
    msg_ok "Started Service"

    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
