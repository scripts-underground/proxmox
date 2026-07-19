#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://homarr.dev/
# shellcheck disable=SC2034
APP="homarr"
var_tags="${var_tags:-arr;dashboard}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
function install_script() {
  NODE_VERSION="22" setup_nodejs
  fetch_and_deploy_gh_release "homarr" "homarr-labs/homarr" "prebuild" "latest" "/opt/homarr" "build-debian-$(get_system_arch).tar.gz"
  msg_info "Installing Homarr"
  mkdir -p /opt/homarr_db
  touch /opt/homarr_db/db.sqlite
  SECRET_ENCRYPTION_KEY="$(openssl rand -hex 32)"
  cd /opt/homarr || exit
  cat << EOF > /opt/homarr.env
DB_DRIVER='better-sqlite3'
DB_DIALECT='sqlite'
SECRET_ENCRYPTION_KEY='${SECRET_ENCRYPTION_KEY}'
DB_URL='/opt/homarr_db/db.sqlite'
TURBO_TELEMETRY_DISABLED=1
AUTH_PROVIDERS='credentials'
NODE_ENV='production'
REDIS_IS_EXTERNAL='true'
EOF
  msg_ok "Installed Homarr"
  msg_info "Copying config files"
  mkdir -p /appdata/redis
  chown -R redis:redis /appdata/redis
  chmod 744 /appdata/redis
  cp /opt/homarr/redis.conf /etc/redis/redis.conf
  sed -i -e '$a\' /etc/redis/redis.conf
  grep -q '^bind 127.0.0.1 -::1$' /etc/redis/redis.conf || echo "bind 127.0.0.1 -::1" >> /etc/redis/redis.conf
  rm -f /etc/nginx/nginx.conf
  mkdir -p /etc/nginx/templates
  cp /opt/homarr/nginx.conf /etc/nginx/templates/nginx.conf
  echo $'#!/bin/bash\nset -a\nsource /opt/homarr.env\nset +a\ncd /opt/homarr/apps/cli && node ./cli.cjs "$@"' > /usr/bin/homarr
  chmod +x /usr/bin/homarr
  msg_ok "Copied config files"
  msg_info "Creating Services"
  mkdir -p /etc/systemd/system/redis-server.service.d/
  cat << 'EOF' > /etc/systemd/system/redis-server.service.d/override.conf
[Service]
ReadWritePaths=-/appdata/redis -/var/lib/redis -/var/log/redis -/var/run/redis -/etc/redis
EOF
  cat << 'EOF' > /etc/systemd/system/homarr.service
[Unit]
Requires=redis-server.service
After=redis-server.service
Description=Homarr Service
After=network.target
[Service]
Type=exec
WorkingDirectory=/opt/homarr
EnvironmentFile=-/opt/homarr.env
ExecStart=/opt/homarr/run.sh
[Install]
WantedBy=multi-user.target
EOF
  chmod +x /opt/homarr/run.sh
  systemctl daemon-reload
  systemctl enable -q --now redis-server
  systemctl enable -q --now homarr
  systemctl disable -q --now nginx
  msg_ok "Created Services"
}
function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:7575${CL}"
}
function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/homarr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_error "Homarr auto-updates. Use the web UI for updates."
  exit
}
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
