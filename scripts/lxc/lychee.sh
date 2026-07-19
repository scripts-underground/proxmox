#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://lycheeorg.github.io/
# shellcheck disable=SC2034
APP="Lychee"
var_tags="${var_tags:-media;photos;gallery}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
function install_script() {
  PHP_VERSION="8.4" PHP_FPM="YES" setup_php
  setup_composer
  PG_VERSION="17" setup_postgresql
  PG_DB_NAME="lychee" PG_DB_USER="lychee" setup_postgresql_db
  setup_ffmpeg
  setup_imagemagick
  fetch_and_deploy_gh_release "lychee" "LycheeOrg/Lychee" "prebuild" "latest" "/opt/lychee" "Lychee.zip"
  msg_info "Configuring Application"
  cd /opt/lychee || exit
  cp .env.example .env
  APP_KEY=$($STD php artisan key:generate --show)
  sed -i "s|^APP_KEY=.*|APP_KEY=${APP_KEY}|" .env
  sed -i "s|^APP_ENV=.*|APP_ENV=production|" .env
  sed -i "s|^DB_CONNECTION=.*|DB_CONNECTION=pgsql|" .env
  sed -i "s|^DB_HOST=.*|DB_HOST=127.0.0.1|" .env
  sed -i "s|^DB_PORT=.*|DB_PORT=5432|" .env
  sed -i "s|^DB_DATABASE=.*|DB_DATABASE=lychee|" .env
  sed -i "s|^DB_USERNAME=.*|DB_USERNAME=lychee|" .env
  sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${PG_DB_PASS}|" .env
  export COMPOSER_ALLOW_SUPERUSER=1
  $STD composer install --no-dev --no-interaction --prefer-dist
  $STD php artisan migrate --force
  chown -R www-data: /opt/lychee
  msg_ok "Configured Lychee"
  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/lychee.service
[Unit]
Description=Lychee Photo Service
After=network.target
[Service]
Type=simple
WorkingDirectory=/opt/lychee
ExecStart=/usr/bin/php8.4 artisan serve --host=0.0.0.0 --port=8000
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now lychee
  msg_ok "Created Service"
}
function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
}
function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/lychee ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating $APP LXC"
  $STD apt update && $STD apt upgrade -y
  msg_ok "Updated $APP LXC"
  msg_ok "Updated successfully!"
  exit
}
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
