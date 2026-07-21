#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2155
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: bvdberg01
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/pelican-dev/panel

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Pelican-Panel"
var_tags="${var_tags:-gaming}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y cron
  msg_ok "Installed Dependencies"

  PHP_VERSION="8.4" PHP_APACHE="YES" PHP_FPM="YES" setup_php
  setup_composer
  setup_mariadb
  MARIADB_DB_NAME="panel" MARIADB_DB_USER="pelican" setup_mariadb_db
  fetch_and_deploy_gh_release "pelican-panel" "pelican-dev/panel" "prebuild" "latest" "/opt/pelican-panel" "panel.tar.gz"

  msg_info "Installing Pelican Panel"
  cd /opt/pelican-panel || exit
  $STD composer install --no-dev --optimize-autoloader --no-interaction
  $STD php artisan p:environment:setup
  $STD php artisan p:environment:queue-service --no-interaction
  echo "* * * * * php /opt/pelican-panel/artisan schedule:run >> /dev/null 2>&1" | crontab -u www-data -
  chown -R www-data:www-data /opt/pelican-panel
  chmod -R 755 /opt/pelican-panel/storage /opt/pelican-panel/bootstrap/cache/
  msg_ok "Installed Pelican Panel"

  msg_info "Creating Service"
  cat << EOF > /etc/apache2/sites-available/pelican.conf
<VirtualHost *:80>
    ServerName pelican
    DocumentRoot /opt/pelican-panel/public
    AllowEncodedSlashes On
    php_value upload_max_filesize 100M
    php_value post_max_size 100M

    <Directory /opt/pelican-panel/public>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog /var/log/apache2/pelican_error.log
    CustomLog /var/log/apache2/pelican_access.log combined
</VirtualHost>
EOF
  $STD a2ensite pelican
  $STD a2enmod rewrite
  $STD a2dissite 000-default.conf
  $STD systemctl reload apache2
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}/installer${CL}"
  echo -e "${INFO}${YW}Database credentials: cat ~/pelican-panel.creds${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/pelican-panel ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  setup_mariadb
  CURRENT_PHP=$(php -v 2> /dev/null | awk '/^PHP/{print $2}' | cut -d. -f1,2)
  setup_composer

  if [[ "$CURRENT_PHP" != "8.4" ]]; then
    msg_info "Migrating PHP $CURRENT_PHP to 8.4"
    $STD apt remove -y php"${CURRENT_PHP//./}"*
    PHP_VERSION="8.4" PHP_APACHE="YES" PHP_FPM="YES" setup_php
    msg_ok "Migrated PHP $CURRENT_PHP to 8.4"
  fi

  if check_for_gh_release "pelican-panel" "pelican-dev/panel"; then
    msg_info "Stopping Service"
    cd /opt/pelican-panel || exit
    $STD php artisan down
    msg_ok "Stopped Service"

    mkdir -p /opt/backup
    cp -a /opt/pelican-panel/.env /opt/backup
    mkdir -p /opt/backup/storage/app/
    cp -a /opt/pelican-panel/storage/app/public /opt/backup/storage/app/

    SQLITE_INSTALL=$(ls /opt/pelican-panel/database/*.sqlite 1> /dev/null 2>&1 && echo "true" || echo "false")
    $SQLITE_INSTALL && cp -r /opt/pelican-panel/database/*.sqlite /opt/backup

    find /opt/pelican-panel -mindepth 1 -maxdepth 1 ! -name 'backup' ! -name 'plugins' -exec rm -rf {} +

    fetch_and_deploy_gh_release "pelican-panel" "pelican-dev/panel" "prebuild" "latest" "/opt/pelican-panel" "panel.tar.gz"

    msg_info "Updating Pelican Panel"
    cp -a /opt/backup/.env /opt/pelican-panel/
    $SQLITE_INSTALL && mv /opt/backup/*.sqlite /opt/pelican-panel/database/
    cp -a /opt/backup/storage/app/public /opt/pelican-panel/storage/app/

    $STD composer install --no-dev --optimize-autoloader --no-interaction
    $STD php artisan p:environment:setup
    $STD php artisan view:clear
    $STD php artisan config:clear
    $STD php artisan filament:optimize
    $STD php artisan migrate --seed --force
    chown -R www-data:www-data /opt/pelican-panel
    chmod -R 755 /opt/pelican-panel/storage /opt/pelican-panel/bootstrap/cache/
    msg_ok "Updated Pelican Panel"

    msg_info "Starting Service"
    $STD php artisan queue:restart
    $STD php artisan up
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
