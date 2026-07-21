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
  msg_info "Installing Dependencies"
  $STD apt install -y caddy libimage-exiftool-perl jpegoptim
  msg_ok "Installed Dependencies"

  PHP_VERSION="8.4" PHP_FPM="YES" PHP_MODULE="bcmath,ldap,exif,gd,intl,imagick,redis,zip,pdo_pgsql,pcntl" setup_php
  setup_composer
  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="lychee" PG_DB_USER="lychee" setup_postgresql_db
  setup_ffmpeg
  setup_imagemagick

  fetch_and_deploy_gh_release "lychee" "LycheeOrg/Lychee" "prebuild" "latest" "/opt/lychee" "Lychee.zip"

  msg_info "Configuring Lychee"
  cd /opt/lychee || exit
  cp .env.example .env
  APP_KEY=$($STD php artisan key:generate --show)
  sed -i "s|^#\?APP_KEY=.*|APP_KEY=${APP_KEY}|" .env
  sed -i "s|^#\?APP_ENV=.*|APP_ENV=production|" .env
  sed -i "s|^#\?APP_DEBUG=.*|APP_DEBUG=false|" .env
  sed -i "s|^#\?APP_URL=.*|APP_URL=http://${LOCAL_IP}|" .env
  sed -i "s|^#\?DB_CONNECTION=.*|DB_CONNECTION=pgsql|" .env
  sed -i "s|^#\?DB_HOST=.*|DB_HOST=127.0.0.1|" .env
  sed -i "s|^#\?DB_PORT=.*|DB_PORT=5432|" .env
  sed -i "s|^#\?DB_DATABASE=.*|DB_DATABASE=${PG_DB_NAME}|" .env
  sed -i "s|^#\?DB_USERNAME=.*|DB_USERNAME=${PG_DB_USER}|" .env
  sed -i "s|^#\?DB_PASSWORD=.*|DB_PASSWORD=${PG_DB_PASS}|" .env
  export COMPOSER_ALLOW_SUPERUSER=1
  $STD composer install --no-dev --no-interaction --prefer-dist
  $STD php artisan migrate --force
  mkdir -p storage/framework/{cache,sessions,views} storage/logs bootstrap/cache public/dist public/uploads public/sym
  touch public/dist/user.css public/dist/custom.js
  chown -R www-data:www-data /opt/lychee
  chmod -R 775 storage bootstrap/cache public
  msg_ok "Configured Lychee"

  msg_info "Configuring Caddy"
  PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
  cat << EOF > /etc/caddy/Caddyfile
:80 {
    root * /opt/lychee/public
    php_fastcgi unix//run/php/php${PHP_VER}-fpm.sock
    file_server
    encode gzip
}
EOF
  usermod -aG www-data caddy
  msg_ok "Configured Caddy"

  systemctl enable -q --now php"${PHP_VER}"-fpm
  systemctl restart caddy
}
function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
}
function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/lychee ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "lychee" "LycheeOrg/Lychee"; then
    msg_info "Stopping Services"
    systemctl stop caddy
    PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
    systemctl stop "php${PHP_VER}-fpm"
    msg_ok "Stopped Services"

    create_backup /opt/lychee/.env /opt/lychee/storage /opt/lychee/public/uploads /opt/lychee/public/dist

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "lychee" "LycheeOrg/Lychee" "prebuild" "latest" "/opt/lychee" "Lychee.zip"

    restore_backup

    msg_info "Updating Application"
    cd /opt/lychee || exit
    export COMPOSER_ALLOW_SUPERUSER=1
    $STD composer install --no-dev --no-interaction --prefer-dist
    $STD php artisan migrate --force
    $STD php artisan config:clear
    $STD php artisan cache:clear
    $STD php artisan optimize
    chown -R www-data:www-data /opt/lychee
    chmod -R 775 storage bootstrap/cache public
    msg_ok "Updated Application"

    msg_info "Starting Services"
    systemctl start "php${PHP_VER}-fpm"
    systemctl start caddy
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
