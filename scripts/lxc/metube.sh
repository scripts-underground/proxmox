#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/alexta69/metube

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="MeTube"
var_tags="${var_tags:-media;youtube}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    aria2 \
    coreutils \
    musl-dev \
    ffmpeg
  msg_ok "Installed Dependencies"

  PYTHON_VERSION="3.13" setup_uv
  NODE_VERSION="24" NODE_MODULE="corepack,pnpm" setup_nodejs

  msg_info "Installing Deno"
  export DENO_INSTALL="/usr/local"
  curl -fsSL https://deno.land/install.sh | $STD sh -s -- -y
  if [[ ":$PATH:" != *":/usr/local/bin:"* ]]; then
    echo -e "\nexport PATH=\"/usr/local/bin:\$PATH\"" >> ~/.bashrc
    # shellcheck disable=SC1090
    source ~/.bashrc
  fi
  msg_ok "Installed Deno"

  fetch_and_deploy_gh_release "metube" "alexta69/metube" "tarball" "latest"

  msg_info "Installing MeTube"
  cd /opt/metube/ui || exit
  if command -v corepack > /dev/null 2>&1; then
    $STD corepack prepare pnpm --activate || true
  fi
  echo 'onlyBuiltDependencies=*' >> .npmrc
  $STD pnpm install --frozen-lockfile
  $STD pnpm run build
  cd /opt/metube || exit
  $STD uv sync
  mkdir -p /opt/metube_downloads /opt/metube_downloads/.metube /opt/metube_downloads/music /opt/metube_downloads/videos
  cat << EOF > /opt/metube/.env
# Storage & Directories
DOWNLOAD_DIR=/opt/metube_downloads
AUDIO_DOWNLOAD_DIR=/opt/metube_downloads/music
STATE_DIR=/opt/metube_downloads/.metube
TEMP_DIR=/opt/metube_downloads

# Download Behavior
DOWNLOAD_MODE=limited
MAX_CONCURRENT_DOWNLOADS=3
DELETE_FILE_ON_TRASHCAN=false
DEFAULT_OPTION_PLAYLIST_STRICT_MODE=false
DEFAULT_OPTION_PLAYLIST_ITEM_LIMIT=0

# File Naming & yt-dlp
OUTPUT_TEMPLATE=%(title)s.%(ext)s
OUTPUT_TEMPLATE_CHAPTER=%(title)s - %(section_number)s %(section_title)s.%(ext)s
OUTPUT_TEMPLATE_PLAYLIST=%(playlist_title)s/%(title)s.%(ext)s
YTDL_OPTIONS={"trim_file_name":200,"extractor_args":{"youtube":{"player_client":["default","-tv_simply"]}}}

# Custom Directories
CUSTOM_DIRS=true
CREATE_CUSTOM_DIRS=true

# Basic Setup
DEFAULT_THEME=auto
LOGLEVEL=INFO
ENABLE_ACCESSLOG=false
EOF
  msg_ok "Installed MeTube"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/metube.service
[Unit]
Description=Metube - YouTube Downloader
After=network.target
[Service]
Type=simple
WorkingDirectory=/opt/metube
EnvironmentFile=/opt/metube/.env
ExecStart=/opt/metube/.venv/bin/python3 app/main.py
Restart=always
User=root
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now metube
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8081${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/metube ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if [[ ":$PATH:" != *":/usr/local/bin:"* ]]; then
    echo -e "\nexport PATH=\"/usr/local/bin:\$PATH\"" >> ~/.bashrc
    # shellcheck disable=SC1090
    source ~/.bashrc
    if ! command -v deno &> /dev/null; then
      export DENO_INSTALL="/usr/local"
      curl -fsSL https://deno.land/install.sh | $STD sh -s -- -y
    else
      $STD deno upgrade
    fi
  fi

  NODE_VERSION="24" NODE_MODULE="corepack,pnpm" setup_nodejs

  if check_for_gh_release "metube" "alexta69/metube"; then
    msg_info "Stopping Service"
    systemctl stop metube
    msg_ok "Stopped Service"

    msg_info "Backing up Old Installation"
    if [[ -d /opt/metube_bak ]]; then
      rm -rf /opt/metube_bak
    fi
    mv /opt/metube /opt/metube_bak
    msg_ok "Backup created"

    fetch_and_deploy_gh_release "metube" "alexta69/metube" "tarball" "latest"

    msg_info "Building Frontend"
    cd /opt/metube/ui || exit
    if command -v corepack > /dev/null 2>&1; then
      $STD corepack prepare pnpm --activate || true
    fi
    echo 'onlyBuiltDependencies=*' >> .npmrc
    $STD pnpm install --frozen-lockfile
    $STD pnpm run build
    msg_ok "Built Frontend"

    PYTHON_VERSION="3.13" setup_uv

    msg_info "Installing Backend Requirements"
    cd /opt/metube || exit
    $STD uv sync
    msg_ok "Installed Backend"

    msg_info "Restoring .env"
    if [[ -f /opt/metube_bak/.env ]]; then
      cp /opt/metube_bak/.env /opt/metube/.env
    fi
    rm -rf /opt/metube_bak
    msg_ok "Restored .env"

    if grep -q 'pipenv' /etc/systemd/system/metube.service; then
      msg_info "Patching systemd Service"
      cat << EOF > /etc/systemd/system/metube.service
[Unit]
Description=Metube - YouTube Downloader
After=network.target
[Service]
Type=simple
WorkingDirectory=/opt/metube
EnvironmentFile=/opt/metube/.env
ExecStart=/opt/metube/.venv/bin/python3 app/main.py
Restart=always
User=root
[Install]
WantedBy=multi-user.target
EOF
      msg_ok "Patched systemd Service"
    fi
    $STD systemctl daemon-reload
    msg_ok "Service Updated"

    msg_info "Starting Service"
    systemctl start metube
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
