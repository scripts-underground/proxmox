#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://invoiceshelf.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="InvoiceShelf"
var_tags="${var_tags:-invoicing;finance;business}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y caddy
  msg_ok "Installed Dependencies"

  PHP_VERSION="8.4" PHP_FPM="YES" PHP_MODULES="bcmath,gd,intl,xml,zip,pdo_pgsql,mbstring,curl,exif" setup_php
  setup_composer
  NODE_VERSION="24" NODE_MODULE="corepack" setup_nodejs
  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="invoiceshelf" PG_DB_USER="invoiceshelf" setup_postgresql_db

  fetch_and_deploy_gh_release "invoiceshelf" "InvoiceShelf/InvoiceShelf" "tarball"

  msg_info "Setting up InvoiceShelf"
  cd /opt/invoiceshelf || exit
  cp .env.example .env
  sed -i "s|^APP_ENV=.*|APP_ENV=production|" .env
  sed -i "s|^APP_DEBUG=.*|APP_DEBUG=false|" .env
  sed -i "s|^APP_URL=.*|APP_URL=http://${LOCAL_IP}|" .env
  sed -i "s|^DB_CONNECTION=.*|DB_CONNECTION=pgsql|" .env
  sed -i "s|^DB_HOST=.*|DB_HOST=127.0.0.1|" .env
  sed -i "s|^DB_PORT=.*|DB_PORT=5432|" .env
  sed -i "s|^DB_DATABASE=.*|DB_DATABASE=${PG_DB_NAME}|" .env
  sed -i "s|^DB_USERNAME=.*|DB_USERNAME=${PG_DB_USER}|" .env
  sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${PG_DB_PASS}|" .env
  COMPOSER_ALLOW_SUPERUSER=1 $STD composer install --no-dev --optimize-autoloader --no-interaction
  $STD php artisan key:generate --force
  $STD corepack pnpm install
  $STD corepack pnpm run build
  mkdir -p storage/framework/{cache,sessions,views} storage/logs bootstrap/cache
  chown -R www-data:www-data /opt/invoiceshelf
  chmod -R 775 storage bootstrap/cache
  $STD php artisan migrate --force
  $STD php artisan storage:link
  msg_ok "Set up InvoiceShelf"

  msg_info "Configuring Caddy"
  PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
  cat << EOF > /etc/caddy/Caddyfile
:80 {
    root * /opt/invoiceshelf/public
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

  if [[ ! -d /opt/invoiceshelf ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "invoiceshelf" "InvoiceShelf/InvoiceShelf"; then
    msg_info "Stopping Services"
    systemctl stop caddy
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    cp /opt/invoiceshelf/.env /opt/invoiceshelf.env.bak
    cp -r /opt/invoiceshelf/storage /opt/invoiceshelf_storage_backup
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "invoiceshelf" "InvoiceShelf/InvoiceShelf" "tarball"

    msg_info "Restoring Data"
    cp /opt/invoiceshelf.env.bak /opt/invoiceshelf/.env
    rm -f /opt/invoiceshelf.env.bak
    cp -r /opt/invoiceshelf_storage_backup/. /opt/invoiceshelf/storage
    rm -rf /opt/invoiceshelf_storage_backup
    msg_ok "Restored Data"

    msg_info "Updating Application"
    cd /opt/invoiceshelf || exit
    $STD composer install --no-dev --optimize-autoloader
    if command -v corepack > /dev/null 2>&1; then
      $STD corepack pnpm install
      $STD corepack pnpm run build
    else
      $STD pnpm install
      $STD pnpm run build
    fi
    $STD php artisan migrate --force
    $STD php artisan optimize:clear
    chown -R www-data:www-data /opt/invoiceshelf
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
