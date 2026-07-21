#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: vhsdream
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://patchmon.net/

# shellcheck disable=SC2034
APP="PatchMon"
var_tags="${var_tags:-monitoring}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    redis-server \
    ca-certificates
  msg_ok "Installed Dependencies"

  PG_VERSION="17" setup_postgresql
  PG_DB_NAME="patchmon_db" PG_DB_USER="patchmon_user" setup_postgresql_db

  msg_info "Configuring PatchMon"
  REDIS_PASS=$(openssl rand -hex 32)
  JWT_SECRET=$(openssl rand -hex 64)
  SESSION_SECRET=$(openssl rand -hex 64)
  AI_ENCRYPTION_KEY=$(openssl rand -hex 64)
  mkdir -p /opt/patchmon/agents
  cat << EOF > /opt/patchmon/.env
DATABASE_URL=postgresql://$PG_DB_USER:$PG_DB_PASS@localhost:5432/$PG_DB_NAME
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=$REDIS_PASS
REDIS_DB=0
JWT_SECRET=$JWT_SECRET
SESSION_SECRET=$SESSION_SECRET
AI_ENCRYPTION_KEY=$AI_ENCRYPTION_KEY
CORS_ORIGIN=http://localhost:3000
AGENT_BINARIES_DIR=/opt/patchmon/agents
EOF
  sed -i "s|^# requirepass .*|requirepass $REDIS_PASS|" /etc/redis/redis.conf
  systemctl restart redis-server
  msg_ok "Configured PatchMon"

  fetch_and_deploy_gh_release "PatchMon" "PatchMon/PatchMon" "singlefile" "latest" "/opt/patchmon" "patchmon-server-linux-$(get_system_arch)"
  mv /opt/patchmon/PatchMon /opt/patchmon/patchmon-server

  msg_info "Fetching PatchMon agent binaries"
  RELEASE=$(get_latest_github_release "PatchMon/PatchMon")
  FILE_URL="https://github.com/PatchMon/PatchMon/releases/download/v${RELEASE}/patchmon-agent-"
  AGENT_NAME=(
    "linux-amd64"
    "linux-arm64"
    "linux-arm"
    "linux-386"
    "freebsd-amd64"
    "freebsd-arm64"
    "freebsd-arm"
    "freebsd-386"
    "windows-amd64.exe"
    "windows-arm64.exe"
  )
  for arch in "${AGENT_NAME[@]}"; do
    curl_with_retry "${FILE_URL}${arch}" "/opt/patchmon/agents/patchmon-agent-${arch}"
    [[ "${arch}" != *.exe ]] && chmod 755 "/opt/patchmon/agents/patchmon-agent-${arch}"
  done
  msg_ok "Fetched PatchMon agent binaries"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/patchmon-server.service
[Unit]
Description=PatchMon Server
After=network.target postgresql.service redis-server.service
Wants=postgresql.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/patchmon
EnvironmentFile=/opt/patchmon/.env
ExecStart=/opt/patchmon/patchmon-server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now patchmon-server
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d "/opt/patchmon" ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "PatchMon" "PatchMon/PatchMon"; then
    msg_info "Stopping Service"
    systemctl stop patchmon-server
    msg_ok "Stopped Service"

    if [[ -d /opt/patchmon/backend ]]; then
      msg_info "Legacy install detected - creating full backup, please wait..."
      $STD tar czf ~/patchmon_legacy.tar.gz /opt/patchmon
      cp /opt/patchmon/backend/.env /opt/legacy.env
      msg_ok "Full backup saved in /root"
      msg_info "Starting migration to PatchMon v2.x.x"
      systemctl disable -q --now nginx
      $STD npm cache clean --force
      $STD apt autoremove --purge -y {nginx,nodejs}
      if [[ -f /etc/apt/sources.list.d/nodesource.sources ]]; then
        cp /etc/apt/sources.list.d/nodesource.sources /etc/apt/sources.list.d/nodesource.sources.bak
        rm -f /etc/apt/sources.list.d/nodesource.sources
      elif [[ -f /etc/apt/sources.list.d/nodesource.list ]]; then
        cp /etc/apt/sources.list.d/nodesource.list /etc/apt/sources.list.d/nodesource.list.bak
        rm -f /etc/apt/sources.list.d/nodesource.list
      fi
      rm -rf /opt/patchmon
      mkdir -p /opt/patchmon/agents
      cp /opt/legacy.env /opt/patchmon/.env
      sed -i -e 's/^PORT=.*/PORT=3000/' \
        -e 's/^NODE_/APP_/' \
        -e '/^SERVER_*/d' \
        -e '/^# API*/,+2d' /opt/patchmon/.env
      cat << EOF >> /opt/patchmon/.env
SESSION_SECRET=$(openssl rand -hex 64)
AI_ENCRYPTION_KEY=$(openssl rand -hex 64)
AGENT_BINARIES_DIR=/opt/patchmon/agents
EOF
      sed -i -e '\|Directory|s|/backend||' \
        -e 's|^ExecStart=.*|ExecStart=/opt/patchmon/patchmon-server|' \
        -e 's|^Environment=NODE_.*|EnvironmentFile=/opt/patchmon/.env|' \
        /etc/systemd/system/patchmon-server.service
      systemctl daemon-reload
      rm /opt/legacy.env
      msg_ok "Migration complete!"
    fi

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "PatchMon" "PatchMon/PatchMon" "singlefile" "latest" "/opt/patchmon" "patchmon-server-linux-$(get_system_arch)"
    mv /opt/patchmon/PatchMon /opt/patchmon/patchmon-server

    msg_info "Fetching PatchMon agent binaries"
    RELEASE=$(get_latest_github_release "PatchMon/PatchMon")
    [[ ! -d /opt/patchmon/agents ]] && mkdir -p /opt/patchmon/agents
    FILE_URL="https://github.com/PatchMon/PatchMon/releases/download/v${RELEASE}/patchmon-agent-"
    AGENT_NAME=(
      "linux-amd64"
      "linux-arm64"
      "linux-arm"
      "linux-386"
      "freebsd-amd64"
      "freebsd-arm64"
      "freebsd-arm"
      "freebsd-386"
      "windows-amd64.exe"
      "windows-arm64.exe"
    )
    for arch in "${AGENT_NAME[@]}"; do
      curl_with_retry "${FILE_URL}${arch}" "/opt/patchmon/agents/patchmon-agent-${arch}"
      [[ "${arch}" != *.exe ]] && chmod 755 "/opt/patchmon/agents/patchmon-agent-${arch}"
    done
    msg_ok "Fetched PatchMon agent binaries"

    msg_info "Starting Service"
    systemctl start patchmon-server
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
