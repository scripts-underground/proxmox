#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: vhsdream
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/nxzai/nextExplorer

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="nextExplorer"
var_tags="${var_tags:-files;documents}"
var_disk="${var_disk:-8}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-3072}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    ripgrep \
    imagemagick \
    ffmpeg \
    libva-drm2 \
    libva2 \
    mesa-va-drivers \
    vainfo
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" setup_nodejs

  fetch_and_deploy_gh_release "nextExplorer" "nxzai/nextExplorer" "tarball" "latest" "/opt/nextExplorer"

  msg_info "Building nextExplorer"
  APP_DIR="/opt/nextExplorer/app"
  LOCAL_IP="$(hostname -I | awk '{print $1}')"
  mkdir -p "$APP_DIR"
  mkdir -p /etc/nextExplorer
  cd /opt/nextExplorer || exit
  export NODE_ENV=production
  $STD npm ci --omit=dev --workspace backend
  mv node_modules "$APP_DIR"
  mv backend/{src,package.json} "$APP_DIR"
  unset NODE_ENV

  export NODE_ENV=development
  export NODE_OPTIONS="--max-old-space-size=2048"
  $STD npm ci --workspace frontend
  $STD npm run -w frontend build -- --sourcemap false
  unset NODE_ENV
  mv frontend/dist/ "$APP_DIR"/src/public
  msg_ok "Built nextExplorer"

  msg_info "Configuring nextExplorer"
  SECRET=$(openssl rand -hex 32)
  cat << EOF > /etc/nextExplorer/.env
NODE_ENV=production
PORT=3000

VOLUME_ROOT=/mnt
CONFIG_DIR=/etc/nextExplorer
CACHE_DIR=/etc/nextExplorer/cache
# USER_ROOT=

PUBLIC_URL=${LOCAL_IP}:3000
# TRUST_PROXY=
# CORS_ORIGINS=

TERMINAL_ENABLED=false

LOG_LEVEL=info
DEBUG=false
ENABLE_HTTP_LOGGING=false

AUTH_ENABLED=true
AUTH_MODE=both
SESSION_SECRET="${SECRET}"
# AUTH_MAX_FAILED=
# AUTH_LOCK_MINUTES=
# AUTH_USER_EMAIL=
# AUTH_USER_PASSWORD=

# OIDC_ENABLED=
# OIDC_ISSUER=
# OIDC_AUTHORIZATION_URL=
# OIDC_TOKEN_URL=
# OIDC_USERINFO_URL=
# OIDC_CLIENT_ID=
# OIDC_CLIENT_SECRET=
# OIDC_CALLBACK_URL=
# OIDC_LOGOUT_URL=
# OIDC_SCOPES=
# OIDC_AUTO_CREATE_USERS=true

# SEARCH_DEEP=
# SEARCH_RIPGREP=
# SEARCH_MAX_FILESIZE=

# ONLYOFFICE_URL=
# ONLYOFFICE_SECRET=
# ONLYOFFICE_LANG=
# ONLYOFFICE_FORCE_SAVE=
# ONLYOFFICE_FILE_EXTENSIONS=

# COLLABORA_URL=
# COLLABORA_DISCOVERY_URL=
# COLLABORA_SECRET=
# COLLABORA_LANG=
# COLLABORA_FILE_EXTENSIONS=

SHOW_VOLUME_USAGE=true
# USER_DIR_ENABLED=
# SKIP_HOME=

# EDITOR_EXTENSIONS=

# FFMPEG_PATH=
# FFPROBE_PATH=

## Hardware acceleration
# FFMPEG_HWACCEL=vaapi
# FFMPEG_HWACCEL_DEVICE=/dev/dri/renderD128
# FFMPEG_HWACCEL_OUTPUT_FORMAT=nv12

FAVORITES_DEFAULT_ICON=outline.StarIcon

SHARES_ENABLED=true
# SHARES_TOKEN_LENGTH=10
# SHARES_MAX_PER_USER=100
# SHARES_DEFAULT_EXPIRY_DAYS=30
# SHARES_GUEST_SESSION_HOURS=24
# SHARES_ALLOW_PASSWORD=true
# SHARES_ALLOW_ANONYMOUS=true
EOF
  chmod 600 /etc/nextExplorer/.env
  $STD useradd -U -s /usr/sbin/nologin -m -d /home/explorer explorer
  chown -R explorer:explorer "$APP_DIR" /etc/nextExplorer
  sed -i "\|version|s|$(jq -cr '.version' ${APP_DIR}/package.json)|$(cat ~/.nextexplorer)|" "$APP_DIR"/package.json
  msg_ok "Configured nextExplorer"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/nextexplorer.service
[Unit]
Description=nextExplorer Service
After=network.target

[Service]
Type=simple
User=explorer
Group=explorer
WorkingDirectory=/opt/nextExplorer/app
EnvironmentFile=/etc/nextExplorer/.env
ExecStart=/usr/bin/node ./src/server.js
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
  $STD systemctl enable -q --now nextexplorer
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

  if [[ ! -d /opt/nextExplorer ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="24" setup_nodejs

  if check_for_gh_release "nextExplorer" "nxzai/nextExplorer"; then
    msg_info "Stopping nextExplorer"
    $STD systemctl stop nextexplorer
    msg_ok "Stopped nextExplorer"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "nextExplorer" "nxzai/nextExplorer" "tarball" "latest" "/opt/nextExplorer"

    msg_info "Updating nextExplorer"
    APP_DIR="/opt/nextExplorer/app"
    mkdir -p "$APP_DIR"
    cd /opt/nextExplorer || exit
    export NODE_ENV=production
    $STD npm ci --omit=dev --workspace backend
    mv node_modules "$APP_DIR"
    mv backend/{src,package.json} "$APP_DIR"
    unset NODE_ENV
    export NODE_ENV=development
    $STD npm ci --workspace frontend
    $STD npm run -w frontend build -- --sourcemap false
    unset NODE_ENV
    mv frontend/dist/ "$APP_DIR"/src/public
    chown -R explorer:explorer "$APP_DIR" /etc/nextExplorer
    sed -i "\|version|s|$(jq -cr '.version' ${APP_DIR}/package.json)|$(cat ~/.nextexplorer)|" "$APP_DIR"/package.json
    sed -i 's/app.js/server.js/' /etc/systemd/system/nextexplorer.service && systemctl daemon-reload
    msg_ok "Updated nextExplorer"

    msg_info "Starting nextExplorer"
    $STD systemctl start nextexplorer
    msg_ok "Started nextExplorer"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
