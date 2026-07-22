#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://gitlab.com/storyteller-platform/storyteller

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Storyteller"
var_tags="${var_tags:-media;ebook;audiobook}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-10240}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    git \
    pkg-config \
    libsqlite3-dev \
    sqlite3 \
    python3-setuptools \
    ffmpeg
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" NODE_MODULE="corepack,yarn" setup_nodejs

  READIUM_ARCH=$(uname -m)
  [[ "$READIUM_ARCH" == "aarch64" ]] && READIUM_ARCH="arm64"
  fetch_and_deploy_gh_release "readium" "readium/cli" "prebuild" "latest" "/opt/readium" "readium_linux_${READIUM_ARCH}.tar.gz"
  ln -sf /opt/readium/readium /usr/local/bin/readium

  fetch_and_deploy_gl_release "storyteller" "storyteller-platform/storyteller" "tarball" "latest" "/opt/storyteller" "" "web-v2"

  msg_info "Setting up Storyteller"
  cd /opt/storyteller || exit

  $STD corepack yarn install --network-timeout 600000
  $STD gcc -g -fPIC -rdynamic -shared web/sqlite/uuid.c -o web/sqlite/uuid.c.so
  STORYTELLER_SECRET_KEY=$(openssl rand -base64 32)
  cat << EOF > /opt/storyteller/.env
STORYTELLER_SECRET_KEY=${STORYTELLER_SECRET_KEY}
STORYTELLER_DATA_DIR=/opt/storyteller/data
PORT=8001
HOSTNAME=0.0.0.0
READIUM_PORT=9000
NODE_ENV=production
NEXT_TELEMETRY_DISABLED=1
EOF
  mkdir -p /opt/storyteller/data
  cat << EOF > ~/storyteller.creds
Storyteller Credentials
=======================
Secret Key: ${STORYTELLER_SECRET_KEY}
EOF
  msg_ok "Set up Storyteller"

  msg_info "Building Storyteller"
  cd /opt/storyteller || exit
  export CI=1
  export NODE_ENV=production
  export NEXT_TELEMETRY_DISABLED=1
  export SQLITE_NATIVE_BINDING=/opt/storyteller/node_modules/better-sqlite3/build/Release/better_sqlite3.node
  $STD corepack yarn workspaces foreach -Rpt --from @storyteller-platform/web --exclude @storyteller-platform/eslint run build
  mkdir -p /opt/storyteller/web/.next/standalone/web/.next/static
  cp -rT /opt/storyteller/web/.next/static /opt/storyteller/web/.next/standalone/web/.next/static
  if [[ -d /opt/storyteller/web/public ]]; then
    mkdir -p /opt/storyteller/web/.next/standalone/web/public
    cp -rT /opt/storyteller/web/public /opt/storyteller/web/.next/standalone/web/public
  fi
  mkdir -p /opt/storyteller/web/.next/standalone/web/migrations
  cp -rT /opt/storyteller/web/migrations /opt/storyteller/web/.next/standalone/web/migrations
  mkdir -p /opt/storyteller/web/.next/standalone/web/sqlite
  cp -rT /opt/storyteller/web/sqlite /opt/storyteller/web/.next/standalone/web/sqlite
  ln -sf /opt/storyteller/.env /opt/storyteller/web/.next/standalone/web/.env
  msg_ok "Built Storyteller"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/storyteller.service
[Unit]
Description=Storyteller
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/storyteller/web/.next/standalone/web
EnvironmentFile=/opt/storyteller/.env
ExecStart=/usr/bin/node --enable-source-maps server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now storyteller
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8001${CL}"
  if [[ -f ~/storyteller.creds ]]; then
    echo -e "${INFO}${YW}Default Credentials:${CL}"
    cat ~/storyteller.creds
  fi
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/storyteller ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="24" NODE_MODULE="corepack,yarn" setup_nodejs

  if check_for_gl_release "storyteller" "storyteller-platform/storyteller" "" "" "web-v2"; then
    msg_info "Stopping Service"
    systemctl stop storyteller
    msg_ok "Stopped Service"

    create_backup /opt/storyteller/.env

    CLEAN_INSTALL=1 fetch_and_deploy_gl_release "storyteller" "storyteller-platform/storyteller" "tarball" "latest" "/opt/storyteller" "" "web-v2"

    restore_backup

    msg_info "Rebuilding Storyteller"
    cd /opt/storyteller || exit
    export NODE_OPTIONS="--max-old-space-size=4096"

    $STD corepack yarn install --network-timeout 600000
    $STD gcc -g -fPIC -rdynamic -shared web/sqlite/uuid.c -o web/sqlite/uuid.c.so
    export CI=1
    export NODE_ENV=production
    export NEXT_TELEMETRY_DISABLED=1
    export SQLITE_NATIVE_BINDING=/opt/storyteller/node_modules/better-sqlite3/build/Release/better_sqlite3.node
    $STD corepack yarn workspaces foreach -Rpt --from @storyteller-platform/web --exclude @storyteller-platform/eslint run build
    mkdir -p /opt/storyteller/web/.next/standalone/web/.next/static
    cp -rT /opt/storyteller/web/.next/static /opt/storyteller/web/.next/standalone/web/.next/static
    if [[ -d /opt/storyteller/web/public ]]; then
      mkdir -p /opt/storyteller/web/.next/standalone/web/public
      cp -rT /opt/storyteller/web/public /opt/storyteller/web/.next/standalone/web/public
    fi
    mkdir -p /opt/storyteller/web/.next/standalone/web/migrations
    cp -rT /opt/storyteller/web/migrations /opt/storyteller/web/.next/standalone/web/migrations
    mkdir -p /opt/storyteller/web/.next/standalone/web/sqlite
    cp -rT /opt/storyteller/web/sqlite /opt/storyteller/web/.next/standalone/web/sqlite
    ln -sf /opt/storyteller/.env /opt/storyteller/web/.next/standalone/web/.env
    msg_ok "Rebuilt Storyteller"

    msg_info "Starting Service"
    systemctl start storyteller
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
