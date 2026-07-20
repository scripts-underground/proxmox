#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: quantumryuu
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://firefly-iii.org/ | Github: https://github.com/firefly-iii/firefly-iii

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Firefly"
var_tags="${var_tags:-finance}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  LOCAL_IP=$(hostname -I | awk '{print $1}')
  export LOCAL_IP

  PHP_VERSION="8.5" PHP_APACHE="YES" setup_php
  setup_composer
  setup_mariadb
  MARIADB_DB_NAME="firefly" MARIADB_DB_USER="firefly" setup_mariadb_db

  fetch_and_deploy_gh_release "firefly" "firefly-iii/firefly-iii" "prebuild" "latest" "/opt/firefly" "FireflyIII-*.zip"
  fetch_and_deploy_gh_release "dataimporter" "firefly-iii/data-importer" "prebuild" "latest" "/opt/firefly/dataimporter" "DataImporter-v*.tar.gz"

  msg_info "Configuring Firefly III (Patience)"
  chown -R www-data:www-data /opt/firefly
  chmod -R 775 /opt/firefly/storage
  cd /opt/firefly || exit
  cp .env.example .env
  sed -i "s/DB_HOST=.*/DB_HOST=localhost/" /opt/firefly/.env
  sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$MARIADB_DB_PASS/" /opt/firefly/.env
  $STD composer install --no-dev --no-plugins --no-interaction
  $STD php artisan firefly:upgrade-database
  $STD php artisan firefly:correct-database
  $STD php artisan firefly:report-integrity
  $STD php artisan firefly:laravel-passport-keys
  msg_ok "Configured Firefly III"

  msg_info "Configuring Data Importer"
  cp /opt/firefly/dataimporter/.env.example /opt/firefly/dataimporter/.env
  sed -i \
    -e "s#FIREFLY_III_URL=#FIREFLY_III_URL=http://${LOCAL_IP}#g" \
    -e "s|^APP_URL=.*|APP_URL=http://${LOCAL_IP}/dataimporter|" \
    -e "s|^ASSET_URL=.*|ASSET_URL=/dataimporter|" \
    /opt/firefly/dataimporter/.env
  cd /opt/firefly/dataimporter || exit
  $STD php artisan config:clear
  chown -R www-data:www-data /opt/firefly
  msg_ok "Configured Data Importer"

  msg_info "Creating Service"
  cat << EOF > /etc/apache2/sites-available/firefly.conf
<VirtualHost *:80>
  ServerAdmin webmaster@localhost
  DocumentRoot /opt/firefly/public/

   <Directory /opt/firefly/public>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
  
  RedirectMatch 301 ^/dataimporter$ /dataimporter/

  Alias /dataimporter/ /opt/firefly/dataimporter/public/

    <Directory /opt/firefly/dataimporter/public/>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    <FilesMatch \.php$>
        SetHandler application/x-httpd-php
    </FilesMatch>

    ErrorLog /var/log/apache2/error.log
    CustomLog /var/log/apache2/access.log combined

</VirtualHost>
EOF
  chown www-data:www-data /opt/firefly/storage/oauth-*.key
  $STD a2enmod php8.5
  $STD a2enmod rewrite
  $STD a2ensite firefly.conf
  $STD a2dissite 000-default.conf
  $STD systemctl reload apache2
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/firefly ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  setup_mariadb
  PHP_VERSION="8.5" PHP_APACHE="YES" setup_php

  if check_for_gh_release "firefly" "firefly-iii/firefly-iii"; then
    systemctl stop apache2
    cp /opt/firefly/.env /opt/.env
    rm -rf /opt/storage
    cp -r /opt/firefly/storage /opt/storage

    if [[ -d /opt/firefly/dataimporter ]]; then
      cp /opt/firefly/dataimporter/.env /opt/dataimporter.env
      IMPORTER_INSTALLED=1
    fi

    fetch_and_deploy_gh_release "firefly" "firefly-iii/firefly-iii" "prebuild" "latest" "/opt/firefly" "FireflyIII-*.zip"
    setup_composer

    msg_info "Updating Firefly"
    rm -rf /opt/firefly/storage
    cp -r /opt/storage /opt/firefly/storage
    cp /opt/.env /opt/firefly/.env

    chown -R www-data:www-data /opt/firefly
    chmod -R 775 /opt/firefly/storage
    mkdir -p /opt/firefly/storage/framework/cache/data
    mkdir -p /opt/firefly/storage/framework/sessions
    mkdir -p /opt/firefly/storage/framework/views
    mkdir -p /opt/firefly/storage/logs
    mkdir -p /opt/firefly/bootstrap/cache
    chown -R www-data:www-data /opt/firefly/storage /opt/firefly/bootstrap/cache
    cd /opt/firefly || exit
    $STD runuser -u www-data -- composer install --no-dev --optimize-autoloader
    $STD runuser -u www-data -- composer dump-autoload -o

    $STD runuser -u www-data -- php artisan cache:clear
    $STD runuser -u www-data -- php artisan config:clear
    $STD runuser -u www-data -- php artisan route:clear
    $STD runuser -u www-data -- php artisan view:clear

    $STD runuser -u www-data -- php artisan migrate --seed --force
    $STD runuser -u www-data -- php artisan firefly-iii:upgrade-database
    $STD runuser -u www-data -- php artisan firefly-iii:laravel-passport-keys

    $STD runuser -u www-data -- php artisan storage:link || true
    $STD runuser -u www-data -- php artisan optimize
    msg_ok "Updated Firefly"

    if [[ "${IMPORTER_INSTALLED:-0}" -eq 1 ]]; then
      CLEAN_INSTALL=1 fetch_and_deploy_gh_release "dataimporter" "firefly-iii/data-importer" "prebuild" "latest" "/opt/firefly/dataimporter" "DataImporter-v*.tar.gz"

      msg_info "Updating Firefly Importer"
      if [[ -f /opt/dataimporter.env ]]; then
        cp /opt/dataimporter.env /opt/firefly/dataimporter/.env
      fi
      chown -R www-data:www-data /opt/firefly/dataimporter
      msg_ok "Updated Firefly Importer"
    fi
    rm -rf /opt/storage /opt/.env /opt/dataimporter.env
    systemctl start apache2
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
