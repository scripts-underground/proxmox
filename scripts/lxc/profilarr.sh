#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: michelroegl-brunner
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Dictionarry-Hub/profilarr

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Profilarr"
var_tags="${var_tags:-arr;radarr;sonarr;config}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-7}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    git \
    libsqlite3-0
  msg_ok "Installed Dependencies"

  ARCH=$(uname -m)
  fetch_and_deploy_gh_release "deno" "denoland/deno" "prebuild" "v2.7.5" "/usr/local/bin" "deno-${ARCH}-unknown-linux-gnu.zip"
  fetch_and_deploy_gh_release "profilarr" "Dictionarry-Hub/profilarr" "tarball"
  PROFILARR_VERSION=$(cat ~/.profilarr)

  msg_info "Building Profilarr v${PROFILARR_VERSION} (Patience)"
  cd /opt/profilarr || exit
  cat > src/lib/shared/build.ts << EOF
// Generated at install time. Do not hand-edit.
export type Channel = 'stable' | 'develop' | 'dev';

export interface BuildInfo {
	readonly version: string;
	readonly channel: Channel;
	readonly commit: string | null;
	readonly builtAt: string | null;
}

export const build: BuildInfo = {
	version: '${PROFILARR_VERSION}',
	channel: 'stable',
	commit: null,
	builtAt: '$(date -u +"%Y-%m-%dT%H:%M:%SZ")'
};
EOF
  $STD deno install --node-modules-dir
  export APP_BASE_PATH=/opt/profilarr/dist/build
  export VITE_CHANNEL=stable
  $STD deno run -A npm:vite build
  DENO_TARGET="${ARCH}-unknown-linux-gnu"
  $STD deno compile \
    --no-check \
    --allow-net \
    --allow-read \
    --allow-write \
    --allow-env \
    --allow-ffi \
    --allow-run \
    --allow-sys \
    --target "$DENO_TARGET" \
    --output dist/build/profilarr \
    dist/build/mod.ts
  msg_ok "Built Profilarr"

  msg_info "Installing Profilarr"
  mkdir -p /opt/profilarr/app
  cp dist/build/profilarr /opt/profilarr/app/profilarr
  cp dist/build/server.js /opt/profilarr/app/server.js
  cp -r dist/build/static /opt/profilarr/app/static
  chmod +x /opt/profilarr/app/profilarr
  mkdir -p /var/lib/profilarr/{data,logs,backups,databases}
  SQLITE_PATH="/usr/lib/${ARCH}-linux-gnu/libsqlite3.so.0"
  cat << EOF > /etc/default/profilarr
PORT=6868
HOST=0.0.0.0
APP_BASE_PATH=/var/lib/profilarr
DENO_SQLITE_PATH=${SQLITE_PATH}
EOF
  msg_ok "Installed Profilarr"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/profilarr.service
[Unit]
Description=Profilarr - Configuration Management for Radarr/Sonarr
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/profilarr/app
EnvironmentFile=/etc/default/profilarr
Environment=HOME=/root
ExecStart=/opt/profilarr/app/profilarr
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now profilarr
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:6868${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/profilarr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if [[ -d /opt/profilarr/backend ]]; then
    msg_error "Profilarr v1 detected!"
    echo -e "\nProfilarr v2 is a complete rewrite and is NOT compatible with v1."
    echo -e "There is no migration path. Please create a new LXC container for v2.\n"
    exit
  fi

  ARCH=$(uname -m)

  if check_for_gh_release "deno" "denoland/deno" "v2.7.5" "Deno is pinned to 2.7.5 because the known WouldBlock: Resource temporarily unavailable (os error 11) Issue"; then
    fetch_and_deploy_gh_release "deno" "denoland/deno" "v2.7.5" "latest" "/usr/local/bin" "deno-${ARCH}-unknown-linux-gnu.zip"
  fi

  if check_for_gh_release "profilarr" "Dictionarry-Hub/profilarr"; then
    msg_info "Stopping Service"
    systemctl stop profilarr
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "profilarr" "Dictionarry-Hub/profilarr" "tarball"
    PROFILARR_VERSION=$(cat ~/.profilarr)

    msg_info "Building Profilarr v${PROFILARR_VERSION} (Patience)"
    cd /opt/profilarr || exit
    cat > src/lib/shared/build.ts << EOF
// Generated at update time. Do not hand-edit.
export type Channel = 'stable' | 'develop' | 'dev';

export interface BuildInfo {
	readonly version: string;
	readonly channel: Channel;
	readonly commit: string | null;
	readonly builtAt: string | null;
}

export const build: BuildInfo = {
	version: '${PROFILARR_VERSION}',
	channel: 'stable',
	commit: null,
	builtAt: '$(date -u +"%Y-%m-%dT%H:%M:%SZ")'
};
EOF
    $STD deno install --node-modules-dir
    export APP_BASE_PATH=/opt/profilarr/dist/build
    export VITE_CHANNEL=stable
    $STD deno run -A npm:vite build
    DENO_TARGET="${ARCH}-unknown-linux-gnu"
    $STD deno compile \
      --no-check \
      --allow-net \
      --allow-read \
      --allow-write \
      --allow-env \
      --allow-ffi \
      --allow-run \
      --allow-sys \
      --target "$DENO_TARGET" \
      --output dist/build/profilarr \
      dist/build/mod.ts
    msg_ok "Built Profilarr"

    msg_info "Updating Profilarr"
    mkdir -p /opt/profilarr/app
    cp dist/build/profilarr /opt/profilarr/app/profilarr
    cp dist/build/server.js /opt/profilarr/app/server.js
    cp -r dist/build/static /opt/profilarr/app/static
    chmod +x /opt/profilarr/app/profilarr
    msg_ok "Updated Profilarr"

    msg_info "Starting Service"
    systemctl start profilarr
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
