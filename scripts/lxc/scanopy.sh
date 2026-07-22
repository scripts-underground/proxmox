#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: vhsdream
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/scanopy/scanopy

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Scanopy"
var_tags="${var_tags:-analytics}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    libssl-dev \
    pkg-config
  msg_ok "Installed Dependencies"

  PG_VERSION=17 setup_postgresql
  NODE_VERSION="24" setup_nodejs
  PG_DB_NAME="scanopy_db" PG_DB_USER="scanopy" PG_DB_GRANT_SUPERUSER="true" setup_postgresql_db

  fetch_and_deploy_gh_release "Scanopy" "scanopy/scanopy" "tarball" "latest" "/opt/scanopy"

  TOOLCHAIN="$(grep "channel" /opt/scanopy/backend/rust-toolchain.toml | awk -F\" '{print $2}')"
  RUST_TOOLCHAIN=$TOOLCHAIN setup_rust

  msg_info "Building Scanopy Server (patience)"
  cd /opt/scanopy/backend || exit
  $STD cargo build --release --bin server --bin generate-fixtures
  $STD ./target/release/generate-fixtures --output-dir /opt/scanopy/ui/src/lib/data
  mv ./target/release/server /usr/bin/scanopy-server
  msg_ok "Built Scanopy Server"

  msg_info "Creating frontend UI"
  export PUBLIC_SERVER_HOSTNAME=default
  export PUBLIC_SERVER_PORT=""
  cd /opt/scanopy/ui || exit
  $STD npm ci --no-fund --no-audit
  $STD npm run build
  msg_ok "Created frontend UI"

  msg_info "Configuring server for first-run"
  cat << EOF > /opt/scanopy/.env
### - SERVER
SCANOPY_DATABASE_URL=postgresql://$PG_DB_USER:$PG_DB_PASS@localhost:5432/$PG_DB_NAME
SCANOPY_WEB_EXTERNAL_PATH="/opt/scanopy/ui/build"
SCANOPY_PUBLIC_URL=http://${LOCAL_IP}:60072
SCANOPY_SERVER_PORT=60072
SCANOPY_LOG_LEVEL=info
SCANOPY_INTEGRATED_DAEMON_URL=http://127.0.0.1:60073
## - uncomment to disable signups
# SCANOPY_DISABLE_REGISTRATION=true
## - uncomment when using TLS
# SCANOPY_USE_SECURE_SESSION_COOKIES=true
## - see https://github.com/imbolc/axum-client-ip?tab=readme-ov-file#configurable-vs-specific-extractors
## - before uncommenting the below
# SCANOPY_CLIENT_IP_SOURCE=

### - SMTP (password reset and notifications - optional)
# SCANOPY_SMTP_RELAY=smtp.gmail.com:587
# SCANOPY_SMTP_USERNAME=your-email@gmail.com
# SCANOPY_SMTP_PASSWORD=your-app-password
# SCANOPY_SMTP_EMAIL=scanopy@yourdomain.tld

### - INTEGRATED DAEMON
SCANOPY_SERVER_URL=http://127.0.0.1:60072
SCANOPY_BIND_ADDRESS=0.0.0.0
SCANOPY_NAME="scanopy-daemon"
SCANOPY_HEARTBEAT_INTERVAL=30

### - see https://github.com/scanopy/scanopy/blob/main/docs/CONFIGURATION.md for more options
EOF

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/scanopy-server.service
[Unit]
Description=Scanopy Network Discovery Server
After=network.target postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/scanopy/backend
EnvironmentFile=/opt/scanopy/.env
ExecStart=/usr/bin/scanopy-server
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  systemctl enable -q --now scanopy-server
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:60072${CL}"
  echo -e "${INFO}${YW} Then create your account, and create a daemon in the UI.${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/scanopy ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "Scanopy" "scanopy/scanopy"; then
    msg_info "Stopping services"
    systemctl stop scanopy-server
    [[ -f /etc/systemd/system/scanopy-daemon.service ]] && systemctl stop scanopy-daemon
    msg_ok "Stopped services"

    create_backup /opt/scanopy/.env /opt/scanopy/oidc.toml

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "Scanopy" "scanopy/scanopy" "tarball" "latest" "/opt/scanopy"

    restore_backup

    ensure_dependencies pkg-config libssl-dev
    TOOLCHAIN="$(grep "channel" /opt/scanopy/backend/rust-toolchain.toml | awk -F\" '{print $2}')"
    RUST_TOOLCHAIN=$TOOLCHAIN setup_rust

    if ! grep -q "PUBLIC_URL" /opt/scanopy/.env; then
      sed -i "\|_PATH=|a\\scanopy_PUBLIC_URL=http://${LOCAL_IP}:60072" /opt/scanopy/.env
    fi
    sed -i 's|_TARGET=.*$|_URL=http://127.0.0.1:60072|' /opt/scanopy/.env

    msg_info "Building Scanopy Server (patience)"
    cd /opt/scanopy/backend || exit
    $STD cargo build --release --bin server --bin generate-fixtures
    $STD ./target/release/generate-fixtures --output-dir /opt/scanopy/ui/src/lib/data
    mv ./target/release/server /usr/bin/scanopy-server
    msg_ok "Built Scanopy Server"

    msg_info "Creating frontend UI"
    PUBLIC_SERVER_HOSTNAME=default
    PUBLIC_SERVER_PORT=""
    export PUBLIC_SERVER_HOSTNAME PUBLIC_SERVER_PORT
    cd /opt/scanopy/ui || exit
    $STD npm ci --no-fund --no-audit
    $STD npm run build
    msg_ok "Created frontend UI"

    if [[ -f /etc/systemd/system/scanopy-daemon.service ]]; then
      fetch_and_deploy_gh_release "Scanopy Daemon" "scanopy/scanopy" "singlefile" "latest" "/usr/local/bin" "scanopy-daemon-linux-$(get_system_arch)"
      mv "/usr/local/bin/Scanopy Daemon" /usr/local/bin/scanopy-daemon
      rm -f /usr/bin/scanopy-daemon ~/configure_daemon.sh
      sed -i -e 's|usr/bin|usr/local/bin|' \
        -e 's/push/daemon_poll/' \
        -e 's/pull/server_poll/' /etc/systemd/system/scanopy-daemon.service
      systemctl daemon-reload
      msg_ok "Updated Scanopy Daemon"
    fi

    msg_info "Starting services"
    systemctl start scanopy-server
    [[ -f /etc/systemd/system/scanopy-daemon.service ]] && systemctl start scanopy-daemon
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
