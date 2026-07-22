#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/transmute-app/transmute

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Transmute"
var_tags="${var_tags:-files;converter}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  UV_PYTHON="3.13" setup_uv
  NODE_VERSION="25" setup_nodejs
  setup_ffmpeg
  setup_gs

  msg_info "Installing Dependencies"
  $STD apt install -y \
    inkscape \
    tesseract-ocr \
    libreoffice-impress \
    libreoffice-common \
    libmagic1 \
    xvfb \
    libsm6 \
    libxext6 \
    libpango-1.0-0 \
    libopengl0 \
    libpangocairo-1.0-0 \
    libgdk-pixbuf-2.0-0 \
    libffi-dev \
    libcairo2 \
    librsvg2-bin \
    unrar-free \
    python3-numpy \
    python3-lxml \
    python3-tinycss2 \
    python3-cssselect
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "pandoc" "jgm/pandoc" "binary" "latest" "" "pandoc-*-$(get_system_arch).deb"

  CALIBRE_ARCH=$(uname -m)
  [[ "$CALIBRE_ARCH" == "aarch64" ]] && CALIBRE_ARCH="arm64"
  fetch_and_deploy_gh_release "calibre" "kovidgoyal/calibre" "prebuild" "latest" "/opt/calibre" "calibre-*-${CALIBRE_ARCH}.txz"
  ln -sf /opt/calibre/ebook-convert /usr/bin/ebook-convert
  ln -sf /usr/local/bin/ffmpeg /usr/bin/ffmpeg

  fetch_and_deploy_gh_release "drawio" "jgraph/drawio-desktop" "binary" "latest" "" "drawio-$(get_system_arch)-*.deb"
  fetch_and_deploy_gh_release "transmute" "transmute-app/transmute" "tarball"

  msg_info "Setting up Python Backend"
  cd /opt/transmute || exit
  $STD uv venv --clear /opt/transmute/.venv
  $STD uv pip install --python /opt/transmute/.venv/bin/python -r requirements.txt
  ln -sf /opt/transmute/.venv/bin/weasyprint /usr/bin/weasyprint
  msg_ok "Set up Python Backend"

  msg_info "Configuring Transmute"
  SECRET_KEY=$(openssl rand -hex 64)
  cat << EOF > /opt/transmute/backend/.env
AUTH_SECRET_KEY=${SECRET_KEY}
HOST=0.0.0.0
PORT=3313
DATA_DIR=/opt/transmute/data
WEB_DIR=/opt/transmute/frontend/dist
QT_QPA_PLATFORM=offscreen
EOF
  mkdir -p /opt/transmute/data
  msg_ok "Configured Transmute"

  msg_info "Building Frontend"
  cd /opt/transmute/frontend || exit
  $STD npm ci
  $STD npm run build
  msg_ok "Built Frontend"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/transmute.service
[Unit]
Description=Transmute File Converter
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/transmute
EnvironmentFile=/opt/transmute/backend/.env
ExecStart=/usr/bin/xvfb-run -a -s "-screen 0 1024x768x24 -nolisten tcp" /opt/transmute/.venv/bin/python backend/main.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now transmute
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3313${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/transmute ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  CALIBRE_ARCH=$(uname -m)
  [[ "$CALIBRE_ARCH" == "aarch64" ]] && CALIBRE_ARCH="arm64"
  fetch_and_deploy_gh_release "calibre" "kovidgoyal/calibre" "prebuild" "latest" "/opt/calibre" "calibre-*-${CALIBRE_ARCH}.txz"
  ln -sf /opt/calibre/ebook-convert /usr/bin/ebook-convert

  fetch_and_deploy_gh_release "drawio" "jgraph/drawio-desktop" "binary" "latest" "" "drawio-$(get_system_arch)-*.deb"
  fetch_and_deploy_gh_release "pandoc" "jgm/pandoc" "binary" "latest" "" "pandoc-*-$(get_system_arch).deb"

  if check_for_gh_release "transmute" "transmute-app/transmute"; then
    msg_info "Stopping Service"
    systemctl stop transmute
    msg_ok "Stopped Service"

    create_backup /opt/transmute/backend/.env /opt/transmute/data
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "transmute" "transmute-app/transmute" "tarball"
    restore_backup

    msg_info "Updating Python Dependencies"
    cd /opt/transmute || exit
    $STD uv venv --clear /opt/transmute/.venv
    $STD uv pip install --python /opt/transmute/.venv/bin/python -r requirements.txt
    msg_ok "Updated Python Dependencies"

    msg_info "Rebuilding Frontend"
    cd /opt/transmute/frontend || exit
    $STD npm ci
    $STD npm run build
    msg_ok "Rebuilt Frontend"

    msg_info "Starting Service"
    systemctl start transmute
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
