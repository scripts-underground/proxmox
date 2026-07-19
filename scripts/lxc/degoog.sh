#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/fccview/degoog
# shellcheck disable=SC2034
APP="degoog"
var_tags="${var_tags:-search;privacy}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
function install_script() {
  msg_info "Installing Bun"
  curl -fsSL https://bun.sh/install | $STD bash
  ln -sf /root/.bun/bin/bun /usr/local/bin/bun
  ln -sf /root/.bun/bin/bunx /usr/local/bin/bunx
  msg_ok "Installed Bun"
  msg_info "Installing Dependencies"
  $STD apt install -y valkey-server
  msg_ok "Installed Dependencies"
  fetch_and_deploy_gh_release "curl-impersonate" "lexiforest/curl-impersonate" "prebuild" "latest" "/usr/local/bin" "curl-impersonate-v*.$(uname -m)-linux-gnu.tar.gz"
  fetch_and_deploy_gh_release "degoog" "fccview/degoog" "prebuild" "latest" "/opt/degoog" "degoog_*_prebuild.tar.gz"
  msg_info "Setting up degoog"
  mkdir -p /opt/degoog/data/{engines,plugins,themes,store}
  SETTINGS_PASS="$(openssl rand -hex 32)"
  cat << EOF > /opt/degoog/.env
DEGOOG_PORT=4444
DEGOOG_ENGINES_DIR=/opt/degoog/data/engines
DEGOOG_PLUGINS_DIR=/opt/degoog/data/plugins
DEGOOG_THEMES_DIR=/opt/degoog/data/themes
DEGOOG_ALIASES_FILE=/opt/degoog/data/aliases.json
DEGOOG_PLUGIN_SETTINGS_FILE=/opt/degoog/data/plugin-settings.json
DEGOOG_VALKEY_URL=redis://127.0.0.1:6379
DEGOOG_CACHE_MAX_ENTRIES=1000
DEGOOG_CACHE_TTL_MS=43200000
DEGOOG_SETTINGS_PASSWORDS=${SETTINGS_PASS}
EOF
  for f in aliases.json plugin-settings.json repos.json; do
    [ -f "/opt/degoog/data/$f" ] || echo '{}' > "/opt/degoog/data/$f"
  done
  msg_ok "Set up degoog"
  msg_info "Starting Valkey Service"
  systemctl enable -q --now valkey-server
  msg_ok "Started Valkey Service"
  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/degoog.service
[Unit]
Description=degoog
After=network.target valkey-server.service
Wants=valkey-server.service
[Service]
Type=simple
User=root
WorkingDirectory=/opt/degoog
EnvironmentFile=/opt/degoog/.env
ExecStart=/usr/local/bin/bun run src/server/index.ts
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now degoog
  msg_ok "Created Service"
}
function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:4444${CL}"
}
function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/degoog ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "degoog" "fccview/degoog"; then
    msg_info "Stopping Service"
    systemctl stop degoog
    msg_ok "Stopped Service"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "degoog" "fccview/degoog" "prebuild" "latest" "/opt/degoog" "degoog_*_prebuild.tar.gz"
    msg_info "Starting Service"
    systemctl start degoog
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
