#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: luismco (luismco)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/ThePhaseless/Byparr

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Byparr"
var_tags="${var_tags:-proxy}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y --no-install-recommends \
    ffmpeg \
    libatk1.0-0 \
    libcairo-gobject2 \
    libcairo2 \
    libdbus-glib-1-2 \
    libfontconfig1 \
    libfreetype6 \
    libgdk-pixbuf-xlib-2.0-0 \
    libglib2.0-0 \
    libgtk-3-0 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libpangoft2-1.0-0 \
    libx11-6 \
    libx11-xcb1 \
    libxcb-shm0 \
    libxcb1 \
    libxcomposite1 \
    libxcursor1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxi6 \
    libxrender1 \
    libxt6 \
    libxtst6 \
    xvfb \
    fonts-noto-color-emoji \
    fonts-unifont \
    xfonts-cyrillic \
    xfonts-scalable \
    fonts-liberation \
    fonts-ipafont-gothic \
    fonts-wqy-zenhei \
    fonts-tlwg-loma-otf
  msg_ok "Installed Dependencies"

  setup_uv
  fetch_and_deploy_gh_release "Byparr" "ThePhaseless/Byparr" "tarball" "latest"

  msg_info "Configuring Byparr"
  cd /opt/Byparr || exit
  $STD uv sync --link-mode copy
  $STD uv run camoufox fetch
  msg_ok "Configured Byparr"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/byparr.service
[Unit]
Description=Byparr
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/Byparr
ExecStart=/usr/local/bin/uv run python3 main.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now byparr
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8191${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/Byparr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "Byparr" "ThePhaseless/Byparr"; then
    msg_info "Stopping Service"
    systemctl stop byparr
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "Byparr" "ThePhaseless/Byparr" "tarball" "latest"

    if ! dpkg -l | grep -q ffmpeg; then
      msg_info "Installing dependencies"
      $STD apt install -y --no-install-recommends \
        ffmpeg \
        libatk1.0-0 \
        libcairo-gobject2 \
        libcairo2 \
        libdbus-glib-1-2 \
        libfontconfig1 \
        libfreetype6 \
        libgdk-pixbuf-xlib-2.0-0 \
        libglib2.0-0 \
        libgtk-3-0 \
        libpango-1.0-0 \
        libpangocairo-1.0-0 \
        libpangoft2-1.0-0 \
        libx11-6 \
        libx11-xcb1 \
        libxcb-shm0 \
        libxcb1 \
        libxcomposite1 \
        libxcursor1 \
        libxdamage1 \
        libxext6 \
        libxfixes3 \
        libxi6 \
        libxrender1 \
        libxt6 \
        libxtst6 \
        xvfb \
        fonts-noto-color-emoji \
        fonts-unifont \
        xfonts-cyrillic \
        xfonts-scalable \
        fonts-liberation \
        fonts-ipafont-gothic \
        fonts-wqy-zenhei \
        fonts-tlwg-loma-otf
      $STD apt autoremove -y chromium
      msg_ok "Installed dependencies"
    fi

    msg_info "Configuring Byparr"
    cd /opt/Byparr || exit
    $STD uv sync --link-mode copy
    $STD uv run camoufox fetch
    msg_ok "Configured Byparr"

    msg_info "Starting Service"
    systemctl start byparr
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
