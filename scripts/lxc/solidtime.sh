#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.solidtime.io/

APP="SolidTime"
var_tags="${var_tags:-time-tracking;productivity;business}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y caddy
  msg_ok "Installed Dependencies"

  PHP_VERSION="8.3" PHP_FPM="YES" PHP_MODULES="bcmath,gd,intl,xml,zip,pdo_pgsql,redis,mbstring,curl" setup_php
  setup_composer
  NODE_VERSION="22" setup_nodejs
  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="solidtime" PG_DB_USER="solidtime" setup_postgresql_db

  fetch_and_deploy_gh_release "solidtime" "solidtime-io/solidtime" "tarball"

  msg_info "Setting up SolidTime"
  cd /opt/solidtime || exit
  cp .env.example .env
  sed -i "s|^APP_ENV=.*|APP_ENV=production|" .env
  sed -i "s|^APP_DEBUG=.*|APP_DEBUG=false|" .env
  sed -i "s|^APP_URL=.*|APP_URL=http://${LOCAL_IP}|" .env
  sed -i "s|^APP_ENABLE_REGISTRATION=.*|APP_ENABLE_REGISTRATION=true|" .env
  sed -i "s|^DB_CONNECTION=.*|DB_CONNECTION=pgsql|" .env
  sed -i "s|^DB_HOST=.*|DB_HOST=127.0.0.1|" .env
  sed -i "s|^DB_PORT=.*|DB_PORT=5432|" .env
  sed -i "s|^DB_DATABASE=.*|DB_DATABASE=${PG_DB_NAME}|" .env
  sed -i "s|^DB_USERNAME=.*|DB_USERNAME=${PG_DB_USER}|" .env
  sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${PG_DB_PASS}|" .env
  sed -i "s|^FILESYSTEM_DISK=.*|FILESYSTEM_DISK=local|" .env
  sed -i "s|^PUBLIC_FILESYSTEM_DISK=.*|PUBLIC_FILESYSTEM_DISK=public|" .env
  sed -i "s|^MAIL_MAILER=.*|MAIL_MAILER=log|" .env
  sed -i "s|^SESSION_SECURE_COOKIE=.*|SESSION_SECURE_COOKIE=false|" .env
  grep -q "^SESSION_SECURE_COOKIE=" .env || echo "SESSION_SECURE_COOKIE=false" >> .env
  sed -i "s|^APP_FORCE_HTTPS=.*|APP_FORCE_HTTPS=false|" .env
  grep -q "^APP_FORCE_HTTPS=" .env || echo "APP_FORCE_HTTPS=false" >> .env
  $STD composer install --no-dev --optimize-autoloader
  php artisan self-host:generate-keys > /tmp/solidtime.keys 2> /dev/null
  while IFS= read -r line; do
    KEY="${line%%=*}"
    [[ -z "$KEY" || "${KEY:0:1}" == "#" ]] && continue
    sed -i "/^${KEY}=/d" .env
    echo "$line" >> .env
  done < /tmp/solidtime.keys
  rm -f /tmp/solidtime.keys
  $STD npm install
  $STD npm run build
  rm -rf node_modules
  mkdir -p storage/framework/{cache,sessions,views} storage/logs bootstrap/cache
  chown -R www-data:www-data /opt/solidtime
  chmod -R 775 storage bootstrap/cache
  $STD php artisan storage:link
  $STD php artisan migrate --force
  $STD php artisan passport:client --personal --name="API" -n
  $STD php artisan optimize:clear
  msg_ok "Set up SolidTime"

  msg_info "Configuring Caddy"
  PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
  cat << EOF > /etc/caddy/Caddyfile
:80 {
    root * /opt/solidtime/public
    php_fastcgi unix//run/php/php${PHP_VER}-fpm.sock
    file_server
    encode gzip
}
EOF
  usermod -aG www-data caddy
  systemctl enable -q --now php${PHP_VER}-fpm
  systemctl restart caddy
  msg_ok "Configured Caddy"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
  echo -e "${INFO}${YW}HTTPS is not enabled by default (use domain + reverse proxy/TLS if needed).${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/solidtime ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "solidtime" "solidtime-io/solidtime"; then
    msg_info "Stopping Services"
    systemctl stop caddy
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    cp /opt/solidtime/.env /opt/solidtime.env.bak
    cp -r /opt/solidtime/storage /opt/solidtime_storage_backup
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "solidtime" "solidtime-io/solidtime" "tarball"

    msg_info "Restoring Data"
    cp /opt/solidtime.env.bak /opt/solidtime/.env
    rm -f /opt/solidtime.env.bak
    cp -r /opt/solidtime_storage_backup/. /opt/solidtime/storage
    rm -rf /opt/solidtime_storage_backup
    msg_ok "Restored Data"

    msg_info "Updating Application"
    cd /opt/solidtime || exit
    $STD composer install --no-dev --optimize-autoloader
    $STD npm install
    $STD npm run build
    $STD php artisan migrate --force
    $STD php artisan optimize:clear
    chown -R www-data:www-data /opt/solidtime
    msg_ok "Updated Application"

    msg_info "Starting Services"
    systemctl start caddy
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
