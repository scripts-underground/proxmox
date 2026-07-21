#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: vhsdream
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/scanopy/scanopy

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Scanopy"
var_tags="${var_tags:-analytics}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y pkg-config libssl-dev
  msg_ok "Installed Dependencies"

  PG_VERSION="17" setup_postgresql
  PG_DB_NAME="scanopy" PG_DB_USER="scanopy" setup_postgresql_db

  NODE_VERSION="24" setup_nodejs
  fetch_and_deploy_gh_release "scanopy" "scanopy/scanopy" "tarball" "latest" "/opt/scanopy"

  TOOLCHAIN="$(grep "channel" /opt/scanopy/backend/rust-toolchain.toml | awk -F\" '{print $2}')"
  RUST_TOOLCHAIN=$TOOLCHAIN RUST_CRATES="cargo" setup_rust

  msg_info "Creating frontend UI"
  export PUBLIC_SERVER_HOSTNAME=default
  export PUBLIC_SERVER_PORT=""
  cd /opt/scanopy/ui || exit
  $STD npm ci --no-fund --no-audit
  $STD npm run build
  msg_ok "Created frontend UI"

  msg_info "Building Scanopy-server (patience)"
  cd /opt/scanopy/backend || exit
  $STD cargo build --release --bin server
  mv ./target/release/server /usr/bin/scanopy-server
  msg_ok "Built Scanopy-server"

  msg_info "Building Scanopy-daemon"
  $STD cargo build --release --bin daemon
  mv ./target/release/daemon /usr/bin/scanopy-daemon
  msg_ok "Built Scanopy-daemon"

  msg_info "Configuring Application"
  cat << EOF > /opt/scanopy/.env
SCANOPY_DATABASE_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}
SCANOPY_PUBLIC_URL=http://${LOCAL_IP}:60072
SCANOPY_LOG_LEVEL=info
EOF
  msg_ok "Configured Application"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/scanopy-server.service
[Unit]
Description=Scanopy Server
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=root
EnvironmentFile=/opt/scanopy/.env
ExecStart=/usr/bin/scanopy-server
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/scanopy-daemon.service
[Unit]
Description=Scanopy Daemon
After=network.target scanopy-server.service
Wants=scanopy-server.service

[Service]
Type=simple
User=root
EnvironmentFile=/opt/scanopy/.env
ExecStart=/usr/bin/scanopy-daemon --url http://127.0.0.1:60072
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now scanopy-server scanopy-daemon
  msg_ok "Created Services"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:60072${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/netvisor ]] && [[ ! -d /opt/scanopy ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping services"
  systemctl -q disable --now netvisor-daemon netvisor-server 2> /dev/null || true
  systemctl -q disable --now scanopy-daemon scanopy-server 2> /dev/null || true
  msg_ok "Stopped services"

  NODE_VERSION="24" setup_nodejs
  CLEAN_INSTALL=1 fetch_and_deploy_gh_release "scanopy" "scanopy/scanopy" "tarball" "latest" "/opt/scanopy"

  ensure_dependencies pkg-config libssl-dev
  TOOLCHAIN="$(grep "channel" /opt/scanopy/backend/rust-toolchain.toml | awk -F\" '{print $2}')"
  RUST_TOOLCHAIN=$TOOLCHAIN RUST_CRATES="cargo" setup_rust

  if [[ -d /opt/netvisor ]]; then
    mv /opt/netvisor/.env /opt/scanopy/.env
    if [[ -f /opt/netvisor/oidc.toml ]]; then
      mv /opt/netvisor/oidc.toml /opt/scanopy/oidc.toml
    fi
    if ! grep -q "PUBLIC_URL" /opt/scanopy/.env; then
      sed -i "\|_PATH=|a\NETVISOR_PUBLIC_URL=http://${LOCAL_IP}:60072" /opt/scanopy/.env
    fi
    sed -i 's|_TARGET=.*$|_URL=http://127.0.0.1:60072|' /opt/scanopy/.env
    sed -i 's/NETVISOR/SCANOPY/g; s|netvisor/|scanopy/|' /opt/scanopy/.env
  fi

  if ! grep -q "SCANOPY_PUBLIC_URL" /opt/scanopy/.env 2> /dev/null; then
    sed -i "s|SCANOPY_PUBLIC_URL=.*|SCANOPY_PUBLIC_URL=http://${LOCAL_IP}:60072|" /opt/scanopy/.env
  fi

  msg_info "Creating frontend UI"
  export PUBLIC_SERVER_HOSTNAME=default
  export PUBLIC_SERVER_PORT=""
  cd /opt/scanopy/ui || exit
  $STD npm ci --no-fund --no-audit
  $STD npm run build
  msg_ok "Created frontend UI"

  msg_info "Building Scanopy-server (patience)"
  cd /opt/scanopy/backend || exit
  $STD cargo build --release --bin server
  mv ./target/release/server /usr/bin/scanopy-server
  msg_ok "Built Scanopy-server"

  msg_info "Building Scanopy-daemon"
  $STD cargo build --release --bin daemon
  mv ./target/release/daemon /usr/bin/scanopy-daemon
  msg_ok "Built Scanopy-daemon"

  if [[ -d /opt/netvisor ]]; then
    sed -i '/^  "server_target.*$/d' /root/.config/daemon/config.json 2> /dev/null || true
    sed -i -e 's|-target|-url|' \
      -e 's| --server-port |:|' \
      -e 's/NetVisor/Scanopy/' \
      -e 's/netvisor/scanopy/' \
      /etc/systemd/system/netvisor-daemon.service 2> /dev/null || true
    mv /etc/systemd/system/netvisor-daemon.service /etc/systemd/system/scanopy-daemon.service 2> /dev/null || true
    sed -i -e 's/NetVisor/Scanopy/' \
      -e 's/netvisor/scanopy/g' \
      /etc/systemd/system/netvisor-server.service 2> /dev/null || true
    mv /etc/systemd/system/netvisor-server.service /etc/systemd/system/scanopy-server.service 2> /dev/null || true
  fi

  systemctl daemon-reload

  msg_info "Starting services"
  systemctl -q enable --now scanopy-server scanopy-daemon
  msg_ok "Updated successfully!"

  if [[ -d /opt/netvisor ]]; then
    sed -i 's/netvisor/scanopy/' /usr/bin/update 2> /dev/null || true
    mv ~/NetVisor.creds ~/scanopy.creds 2> /dev/null || true
    rm -f ~/.netvisor
    rm -rf /opt/netvisor
  fi
  exit
}

function uninstall_script() {
  header_info
  msg_info "Stopping services"
  systemctl -q disable --now scanopy-daemon scanopy-server
  msg_ok "Stopped services"

  msg_info "Removing service files"
  rm -f /etc/systemd/system/scanopy-server.service
  rm -f /etc/systemd/system/scanopy-daemon.service
  systemctl daemon-reload
  msg_ok "Removed service files"

  msg_info "Removing application files"
  rm -rf /opt/scanopy
  rm -f /usr/bin/scanopy-server
  rm -f /usr/bin/scanopy-daemon
  rm -f ~/scanopy.creds
  msg_ok "Removed application files"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
