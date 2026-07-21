#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/foldergram/foldergram

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Foldergram"
var_tags="${var_tags:-photos}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y --no-install-recommends ffmpeg
  msg_ok "Installed Dependencies"

  NODE_MODULE="corepack" NODE_VERSION="25" setup_nodejs
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

  fetch_and_deploy_gh_release "foldergram" "foldergram/foldergram" "tarball"

  msg_info "Setting up Foldergram"
  cd /opt/foldergram || exit
  mkdir -p /opt/foldergram_media
  cat << EOF > /opt/foldergram_media/foldergram.env
NODE_ENV=production
SERVER_PORT=4141
DATA_ROOT=/opt/foldergram_media
GALLERY_ROOT=/opt/foldergram_media/gallery
DB_DIR=/opt/foldergram_media/db
THUMBNAILS_DIR=/opt/foldergram_media/thumbnails
PREVIEWS_DIR=/opt/foldergram_media/previews
GALLERY_EXCLUDED_FOLDERS=
IMAGE_DETAIL_SOURCE=preview
DERIVATIVE_MODE=eager
EOF
  $STD pnpm install
  $STD pnpm run build
  msg_ok "Set up Foldergram"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/foldergram.service
[Unit]
Description=Foldergram Service
After=network.target

[Service]
WorkingDirectory=/opt/foldergram
ExecStart=/usr/bin/pnpm start
Restart=always
EnvironmentFile=/opt/foldergram_media/foldergram.env

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now foldergram
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:4141${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/foldergram ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "foldergram" "foldergram/foldergram"; then
    msg_info "Stopping Service"
    systemctl stop foldergram
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "foldergram" "foldergram/foldergram" "tarball"

    msg_info "Installing Foldergram"
    cd /opt/foldergram || exit
    $STD pnpm install
    $STD pnpm run build
    msg_ok "Installed Foldergram"

    msg_info "Starting Service"
    systemctl start foldergram
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
