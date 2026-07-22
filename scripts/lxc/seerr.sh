#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://docs.seerr.dev/ | Github: https://github.com/seerr-team/seerr

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Seerr"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-12}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    python3-setuptools
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "seerr" "seerr-team/seerr" "tarball"
  pnpm_desired=$(grep -Po '"pnpm":\s*"\K[^"]+' /opt/seerr/package.json)
  NODE_VERSION="22" NODE_MODULE="pnpm@$pnpm_desired" setup_nodejs

  msg_info "Installing Seerr (Patience)"
  export CYPRESS_INSTALL_BINARY=0
  cd /opt/seerr || exit
  $STD pnpm install --frozen-lockfile
  export NODE_OPTIONS="--max-old-space-size=3072"
  $STD pnpm build
  mkdir -p /etc/seerr/
  cat << EOF > /etc/seerr/seerr.conf
## Seerr's default port is 5055, if you want to use both, change this.
## specify on which port to listen
PORT=5055

## specify on which interface to listen, by default seerr listens on all interfaces
HOST=0.0.0.0

## Uncomment if you want to force Node.js to resolve IPv4 before IPv6 (advanced users only)
# FORCE_IPV4_FIRST=true
EOF
  msg_ok "Installed Seerr"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/seerr.service
[Unit]
Description=Seerr Service
Wants=network-online.target
After=network-online.target

[Service]
EnvironmentFile=/etc/seerr/seerr.conf
Environment=NODE_ENV=production
Type=exec
Restart=on-failure
WorkingDirectory=/opt/seerr
ExecStart=/usr/bin/node dist/index.js

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now seerr
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:5055${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/seerr && ! -d /opt/jellyseerr && ! -d /opt/overseerr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Start Migration from Jellyseerr
  if [[ -f /etc/systemd/system/jellyseerr.service ]]; then
    msg_info "Stopping Jellyseerr"
    $STD systemctl stop jellyseerr || true
    $STD systemctl disable jellyseerr || true
    [ -f /etc/systemd/system/jellyseerr.service ] && rm -f /etc/systemd/system/jellyseerr.service
    msg_ok "Stopped Jellyseerr"

    msg_info "Creating Backup (Patience)"
    tar -czf "/opt/jellyseerr_backup_$(date +%Y%m%d_%H%M%S).tar.gz" -C /opt jellyseerr
    msg_ok "Created Backup"

    msg_info "Migrating Jellyseerr to seerr"
    [ -d /opt/jellyseerr ] && mv /opt/jellyseerr /opt/seerr
    [ -d /etc/jellyseerr ] && mv /etc/jellyseerr /etc/seerr
    [ -f /etc/seerr/jellyseerr.conf ] && mv /etc/seerr/jellyseerr.conf /etc/seerr/seerr.conf
    cat << EOF > /etc/systemd/system/seerr.service
[Unit]
Description=Seerr Service
Wants=network-online.target
After=network-online.target

[Service]
EnvironmentFile=/etc/seerr/seerr.conf
Environment=NODE_ENV=production
Type=exec
Restart=on-failure
WorkingDirectory=/opt/seerr
ExecStart=/usr/bin/node dist/index.js

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable -q --now seerr
    msg_ok "Migrated Jellyserr to Seerr"
  fi
  # END Jellyseerr Migration

  # Start Migration from Overseerr
  if [[ -f /etc/systemd/system/overseerr.service ]]; then
    msg_info "Stopping Overseerr"
    $STD systemctl stop overseerr || true
    $STD systemctl disable overseerr || true
    [ -f /etc/systemd/system/overseerr.service ] && rm -f /etc/systemd/system/overseerr.service
    msg_ok "Stopped Overseerr"

    msg_info "Creating Backup (Patience)"
    tar -czf "/opt/overseerr_backup_$(date +%Y%m%d_%H%M%S).tar.gz" -C /opt overseerr
    msg_ok "Created Backup"

    msg_info "Migrating Overseerr to seerr"
    [ -d /opt/overseerr ] && mv /opt/overseerr /opt/seerr
    mkdir -p /etc/seerr
    cat << EOF > /etc/seerr/seerr.conf
## Seerr's default port is 5055, if you want to use both, change this.
## specify on which port to listen
PORT=5055

## specify on which interface to listen, by default seerr listens on all interfaces
#HOST=127.0.0.1

## Uncomment if you want to force Node.js to resolve IPv4 before IPv6 (advanced users only)
# FORCE_IPV4_FIRST=true
EOF
    cat << EOF > /etc/systemd/system/seerr.service
[Unit]
Description=Seerr Service
Wants=network-online.target
After=network-online.target

[Service]
EnvironmentFile=/etc/seerr/seerr.conf
Environment=NODE_ENV=production
Type=exec
Restart=on-failure
WorkingDirectory=/opt/seerr
ExecStart=/usr/bin/node dist/index.js

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable -q --now seerr
    msg_ok "Migrated Overseerr to Seerr"
  fi
  # END Overseerr Migration

  if check_for_gh_release "seerr" "seerr-team/seerr"; then
    msg_info "Stopping Service"
    systemctl stop seerr
    msg_ok "Stopped Service"

    msg_info "Creating Backup"
    cp -a /opt/seerr/config /opt/seerr_backup
    msg_ok "Created Backup"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "seerr" "seerr-team/seerr" "tarball"

    msg_info "Installing Dependencies"
    $STD apt install -y \
      build-essential \
      python3-setuptools
    msg_ok "Installed Dependencies"

    msg_info "Updating PNPM Version"
    pnpm_desired=$(grep -Po '"pnpm":\s*"\K[^"]+' /opt/seerr/package.json)
    NODE_VERSION="22" NODE_MODULE="pnpm@$pnpm_desired" setup_nodejs
    msg_ok "Updated PNPM Version"

    msg_info "Updating Seerr"
    cd /opt/seerr || exit
    rm -rf dist .next node_modules
    export CYPRESS_INSTALL_BINARY=0
    $STD pnpm install --frozen-lockfile
    export NODE_OPTIONS="--max-old-space-size=3072"
    $STD pnpm build
    msg_ok "Updated Seerr"

    msg_info "Restoring Backup"
    rm -rf /opt/seerr/config
    mv /opt/seerr_backup /opt/seerr/config
    msg_ok "Restored Backup"

    msg_info "Starting Service"
    systemctl start seerr
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
