#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://akaunting.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Akaunting"
var_tags="${var_tags:-accounting;finance;erp}"
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
    caddy \
    build-essential \
    python3
  msg_ok "Installed Dependencies"

  PHP_VERSION="8.3" PHP_FPM="YES" PHP_MODULES="bcmath,gd,intl,xml,zip,pdo_mysql,mbstring,curl" setup_php
  setup_composer
  setup_mariadb
  NODE_VERSION="20" setup_nodejs
  MARIADB_DB_NAME="akaunting" MARIADB_DB_USER="akaunting" setup_mariadb_db

  fetch_and_deploy_gh_release "akaunting" "akaunting/akaunting" "tarball"

  msg_info "Setting up Akaunting"
  cd /opt/akaunting || exit
  $STD composer install --no-dev --optimize-autoloader
  $STD npm install
  $STD npm run production
  cat << EOF > /opt/akaunting/.env
APP_NAME=Akaunting
APP_ENV=production
APP_DEBUG=false
APP_KEY=
APP_URL=http://${LOCAL_IP}

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=${MARIADB_DB_NAME}
DB_USERNAME=${MARIADB_DB_USER}
DB_PASSWORD=${MARIADB_DB_PASS}

CACHE_DRIVER=file
SESSION_DRIVER=file
QUEUE_CONNECTION=sync
EOF
  $STD php artisan key:generate --force
  mkdir -p storage/framework/{cache,sessions,views} storage/logs bootstrap/cache
  chown -R www-data:www-data /opt/akaunting
  chmod -R 775 storage bootstrap/cache
  $STD php artisan migrate --force
  msg_ok "Set up Akaunting"

  msg_info "Configuring Caddy"
  PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
  cat << EOF > /etc/caddy/Caddyfile
:80 {
    root * /opt/akaunting/public
    @public path /public/*
    uri @public strip_prefix /public
    php_fastcgi unix//run/php/php${PHP_VER}-fpm.sock
    file_server
    encode gzip
}
EOF
  usermod -aG www-data caddy
  msg_ok "Configured Caddy"

  systemctl enable -q --now php${PHP_VER}-fpm
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

  if [[ ! -d /opt/akaunting ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "akaunting" "akaunting/akaunting"; then
    msg_info "Stopping Services"
    systemctl stop caddy
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    cp /opt/akaunting/.env /opt/akaunting.env.bak
    cp -r /opt/akaunting/storage /opt/akaunting_storage_backup
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "akaunting" "akaunting/akaunting" "tarball"

    msg_info "Restoring Data"
    cp /opt/akaunting.env.bak /opt/akaunting/.env
    rm -f /opt/akaunting.env.bak
    cp -r /opt/akaunting_storage_backup/. /opt/akaunting/storage
    rm -rf /opt/akaunting_storage_backup
    msg_ok "Restored Data"

    msg_info "Updating Application"
    cd /opt/akaunting || exit
    $STD composer install --no-dev --optimize-autoloader
    $STD npm install
    $STD npm run production
    $STD php artisan migrate --force
    $STD php artisan optimize:clear
    chown -R www-data:www-data /opt/akaunting
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

