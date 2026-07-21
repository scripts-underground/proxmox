#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# Co-Author: remz1337
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Brandawg93/PeaNUT/

# shellcheck disable=SC2034
APP="PeaNUT"
var_tags="${var_tags:-network;ups}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-7}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing NUT"
  $STD apt install -y nut-client
  msg_ok "Installed NUT"

  NODE_VERSION="24" NODE_MODULE="pnpm" setup_nodejs
  fetch_and_deploy_gh_release "peanut" "Brandawg93/PeaNUT" "tarball" "latest" "/opt/peanut"

  msg_info "Setup Peanut"
  cd /opt/peanut || exit
  $STD pnpm i
  $STD pnpm run build:local
  cp -r .next/static .next/standalone/.next/
  mkdir -p /opt/peanut/.next/standalone/config
  mkdir -p /etc/peanut/
  ln -sf .next/standalone/server.js server.js
  if [[ ! -f /etc/peanut/settings.yml ]]; then
    cat << EOF > /etc/peanut/settings.yml
NUT_SERVERS: []
EOF
  fi
  ln -sf /etc/peanut/settings.yml /opt/peanut/.next/standalone/config/settings.yml
  cat << EOF > /etc/peanut/peanut.env
NODE_ENV=production

#WEB_HOST=0.0.0.0
#WEB_PORT=8080
#NUT_HOST=localhost
#NUT_PORT=3493

# Disable auth entirely:
#AUTH_DISABLED=true

# Bootstrap initial account on first start (ignored afterwards):
#WEB_USERNAME=admin
#WEB_PASSWORD=changeme
EOF
  chmod 600 /etc/peanut/peanut.env
  msg_ok "Setup Peanut"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/peanut.service
[Unit]
Description=Peanut
After=network.target
[Service]
SyslogIdentifier=peanut
Restart=always
RestartSec=5
Type=simple
EnvironmentFile=/etc/peanut/peanut.env
WorkingDirectory=/opt/peanut
ExecStart=node /opt/peanut/entrypoint.mjs
TimeoutStopSec=30
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now peanut
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/peanut.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="24" NODE_MODULE="pnpm" setup_nodejs

  if check_for_gh_release "PeaNUT" "Brandawg93/PeaNUT"; then
    msg_info "Stopping Service"
    systemctl stop peanut
    msg_info "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "PeaNUT" "Brandawg93/PeaNUT" "tarball" "latest" "/opt/peanut"

    if ! grep -q '/opt/peanut/entrypoint.mjs' /etc/systemd/system/peanut.service; then
      msg_info "Fixing entrypoint"
      cd /opt/peanut || exit
      sed -i 's|/opt/peanut/.next/standalone/server.js|/opt/peanut/entrypoint.mjs|' /etc/systemd/system/peanut.service
      systemctl daemon-reload
      msg_ok "Fixed entrypoint"
    fi

    if [[ ! -f /etc/peanut/peanut.env ]]; then
      msg_info "Migrating service to EnvironmentFile"
      mkdir -p /etc/peanut
      cat << EOF > /etc/peanut/peanut.env
NODE_ENV=production

#WEB_HOST=0.0.0.0
#WEB_PORT=8080
#NUT_HOST=localhost
#NUT_PORT=3493

# Disable auth entirely:
#AUTH_DISABLED=true

# Bootstrap initial account on first start (ignored afterwards):
#WEB_USERNAME=admin
#WEB_PASSWORD=changeme
EOF
      chmod 600 /etc/peanut/peanut.env
      sed -i '/^Environment=/d' /etc/systemd/system/peanut.service
      if ! grep -q '^EnvironmentFile=/etc/peanut/peanut.env' /etc/systemd/system/peanut.service; then
        sed -i '/^Type=simple/a EnvironmentFile=/etc/peanut/peanut.env' /etc/systemd/system/peanut.service
      fi
      systemctl daemon-reload
      msg_ok "Migrated to /etc/peanut/peanut.env"
    fi

    msg_info "Updating PeaNUT"
    cd /opt/peanut || exit
    $STD pnpm i
    $STD pnpm run build:local
    cp -r .next/static .next/standalone/.next/
    mkdir -p /opt/peanut/.next/standalone/config
    ln -sf /etc/peanut/settings.yml /opt/peanut/.next/standalone/config/settings.yml
    ln -sf .next/standalone/server.js server.js
    msg_ok "Updated PeaNUT"

    msg_info "Starting Service"
    systemctl start peanut
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
