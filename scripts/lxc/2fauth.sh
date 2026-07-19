#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: jkrgr0
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://docs.2fauth.app/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="2FAuth"
var_tags="${var_tags:-2fa;authenticator}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y nginx
  msg_ok "Installed Dependencies"

  export PHP_VERSION="8.4"
  PHP_FPM="YES" setup_php
  setup_composer
  setup_mariadb
  MARIADB_DB_NAME="2fauth_db" MARIADB_DB_USER="2fauth" setup_mariadb_db

  fetch_and_deploy_gh_release "2fauth" "Bubka/2FAuth" "tarball"

  msg_info "Setup 2FAuth"
  cd /opt/2fauth || exit
  cp .env.example .env
  sed -i -e "s|^APP_URL=.*|APP_URL=http://$LOCAL_IP|" \
    -e "s|^DB_CONNECTION=$|DB_CONNECTION=mysql|" \
    -e "s|^DB_DATABASE=$|DB_DATABASE=$MARIADB_DB_NAME|" \
    -e "s|^DB_HOST=$|DB_HOST=127.0.0.1|" \
    -e "s|^DB_PORT=$|DB_PORT=3306|" \
    -e "s|^DB_USERNAME=$|DB_USERNAME=$MARIADB_DB_USER|" \
    -e "s|^DB_PASSWORD=$|DB_PASSWORD=$MARIADB_DB_PASS|" .env
  export COMPOSER_ALLOW_SUPERUSER=1
  $STD composer update --no-plugins --no-scripts
  $STD composer install --no-dev --prefer-dist --no-plugins --no-scripts
  $STD php artisan key:generate --force
  $STD php artisan migrate:refresh
  $STD php artisan passport:install -q -n
  $STD php artisan storage:link
  $STD php artisan config:cache
  $STD php artisan 2fauth:fix-passport-key-permissions
  chown -R www-data: /opt/2fauth
  chmod -R 755 /opt/2fauth
  msg_ok "Setup 2FAuth"

  msg_info "Configure Service"
  cat << EOF > /etc/nginx/conf.d/2fauth.conf
server {
  listen 80;
  root /opt/2fauth/public;
  server_name $LOCAL_IP;
  index index.php;
  charset utf-8;

  location / {
    try_files \$uri \$uri/ /index.php?\$query_string;
  }

  location = /favicon.ico { access_log off; log_not_found off; }
  location = /robots.txt { access_log off; log_not_found off; }

  error_page 404 /index.php;

  location ~ \.php\$ {
    fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
    fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
    include fastcgi_params;
  }

  location ~ /\.(?!well-known).* {
    deny all;
  }
}
EOF
  systemctl reload nginx
  msg_ok "Configured Service"
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

  if [[ ! -d /opt/2fauth ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  setup_mariadb
  if check_for_gh_release "2fauth" "Bubka/2FAuth"; then
    $STD apt update
    $STD apt -y upgrade

    msg_info "Creating Backup"
    create_backup \
      /opt/2fauth/.env \
      /opt/2fauth/storage

    if ! dpkg -l | grep -q 'php8.4'; then
      cp /etc/nginx/conf.d/2fauth.conf /etc/nginx/conf.d/2fauth.conf.bak
    fi
    msg_ok "Backup Created"

    if ! dpkg -l | grep -q 'php8.4'; then
      PHP_VERSION="8.4" PHP_FPM="YES" setup_php
      sed -i 's/php8\.[0-9]/php8.4/g' /etc/nginx/conf.d/2fauth.conf
    fi

    fetch_and_deploy_gh_release "2fauth" "Bubka/2FAuth" "tarball"
    setup_composer
    restore_backup

    msg_info "Configuring 2FAuth"
    cd /opt/2fauth || exit
    export COMPOSER_ALLOW_SUPERUSER=1
    $STD composer install --no-dev --prefer-dist
    php artisan 2fauth:install
    chown -R www-data: /opt/2fauth
    chmod -R 755 /opt/2fauth
    $STD php artisan 2fauth:fix-passport-key-permissions
    $STD systemctl restart php8.4-fpm
    $STD systemctl restart nginx
    msg_ok "Configured 2FAuth"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
