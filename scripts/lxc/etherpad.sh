#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: John McLear (JohnMcLear)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://etherpad.org

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Etherpad"
var_tags="${var_tags:-docs;collaboration;editor}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    pkg-config \
    libsqlite3-dev
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" setup_nodejs

  msg_info "Enabling pnpm via corepack"
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  $STD corepack enable
  msg_ok "Enabled pnpm"

  msg_info "Creating etherpad User"
  addgroup --system etherpad
  useradd --system --create-home --home-dir /var/lib/etherpad --shell /usr/sbin/nologin etherpad -g etherpad
  msg_ok "Created etherpad User"

  fetch_and_deploy_gh_release "etherpad-lite" "ether/etherpad" "tarball"

  msg_info "Building Etherpad"
  cd /opt/etherpad-lite || exit
  $STD pnpm install --frozen-lockfile
  $STD pnpm run build:etherpad
  msg_ok "Built Etherpad"

  msg_info "Configuring Etherpad"
  cp /opt/etherpad-lite/settings.json.template /opt/etherpad-lite/settings.json
  install -d -o etherpad -g etherpad -m 0750 /var/lib/etherpad
  sed -i \
    -e 's#"ip" *: *"127.0.0.1"#"ip": "0.0.0.0"#' \
    -e 's#"dbType" *: *"dirty"#"dbType": "sqlite"#' \
    -e 's#"filename" *: *"var/dirty.db"#"filename": "/var/lib/etherpad/etherpad.db"#' \
    /opt/etherpad-lite/settings.json
  chown -R etherpad:etherpad /opt/etherpad-lite
  msg_ok "Configured Etherpad"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/etherpad.service
[Unit]
Description=Etherpad Collaborative Editor
Documentation=https://etherpad.org/doc
After=network.target

[Service]
Type=simple
User=etherpad
Group=etherpad
WorkingDirectory=/opt/etherpad-lite
Environment=NODE_ENV=production
ExecStart=/usr/bin/pnpm run prod
Restart=always
RestartSec=5
LimitNOFILE=65536
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now etherpad
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9001${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/etherpad-lite ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "etherpad-lite" "ether/etherpad"; then
    msg_info "Stopping Service"
    systemctl stop etherpad
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration"
    [ -f /opt/etherpad-lite/settings.json ] && cp /opt/etherpad-lite/settings.json /opt/etherpad-settings.json.bak
    [ -d /opt/etherpad-lite/var ] && cp -a /opt/etherpad-lite/var /opt/etherpad-var.bak
    msg_ok "Backed up Configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "etherpad-lite" "ether/etherpad" "tarball"

    msg_info "Rebuilding Etherpad"
    cd /opt/etherpad-lite || exit
    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
    $STD corepack enable
    $STD pnpm install --frozen-lockfile
    $STD pnpm run build:etherpad
    msg_ok "Rebuilt Etherpad"

    msg_info "Restoring Configuration"
    [ -f /opt/etherpad-settings.json.bak ] && mv /opt/etherpad-settings.json.bak /opt/etherpad-lite/settings.json
    [ -d /opt/etherpad-var.bak ] && rm -rf /opt/etherpad-lite/var && mv /opt/etherpad-var.bak /opt/etherpad-lite/var
    chown -R etherpad:etherpad /opt/etherpad-lite
    msg_ok "Restored Configuration"

    msg_info "Starting Service"
    systemctl start etherpad
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")

