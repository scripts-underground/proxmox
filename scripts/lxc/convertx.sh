#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Omar Minaya | MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/C4illin/ConvertX

# shellcheck disable=SC2034
APP="ConvertX"
var_tags="${var_tags:-converter}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

function install_script() {
  setup_imagemagick

  msg_info "Installing Dependencies"
  $STD apt install -y \
    assimp-utils \
    calibre \
    dcraw \
    dvisvgm \
    ffmpeg \
    inkscape \
    libreoffice-writer \
    libva2 \
    libvips-tools \
    lmodern \
    mupdf-tools \
    pandoc \
    poppler-utils \
    potrace \
    python3-numpy \
    texlive \
    texlive-fonts-recommended \
    texlive-latex-extra \
    texlive-latex-recommended \
    texlive-xetex
  msg_ok "Installed Dependencies"

  setup_hwaccel

  NODE_VERSION="22" NODE_MODULE="bun" setup_nodejs

  fetch_and_deploy_gh_release "ConvertX" "C4illin/ConvertX" "tarball"

  msg_info "Installing ConvertX"
  cd /opt/convertx || exit
  mkdir -p data
  $STD bun install

  JWT_SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
  cat << EOF > /opt/convertx/.env
JWT_SECRET=$JWT_SECRET
HTTP_ALLOWED=true
PORT=3000
EOF
  msg_ok "Installed ConvertX"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/convertx.service
[Unit]
Description=ConvertX File Converter
After=network.target

[Service]
Type=exec
WorkingDirectory=/opt/convertx
EnvironmentFile=/opt/convertx/.env
ExecStart=/bin/bun dev
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now convertx
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/convertx ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "ConvertX" "C4illin/ConvertX"; then
    msg_info "Stopping Service"
    systemctl stop convertx
    msg_ok "Stopped Service"

    ensure_dependencies libreoffice-writer

    create_backup /opt/convertx/data

    fetch_and_deploy_gh_release "ConvertX" "C4illin/ConvertX" "tarball"

    restore_backup

    msg_info "Updating ConvertX"
    cd /opt/convertx || exit
    $STD bun install
    msg_ok "Updated ConvertX"

    msg_info "Starting Service"
    systemctl start convertx
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
