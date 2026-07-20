#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: bvdberg01
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.monicahq.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Monica"
var_tags="${var_tags:-network}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  PHP_VERSION="8.2" PHP_APACHE="YES" PHP_MODULE="mysqli,pdo-mysql" setup_php
  setup_composer
  setup_mariadb
  MARIADB_DB_NAME="monica" MARIADB_DB_USER="monica" setup_mariadb_db
  NODE_VERSION="22" NODE_MODULE="yarn@latest" setup_nodejs
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "monica" "monicahq/monica" "prebuild" "latest" "/opt/monica" "monica-v*.tar.bz2"

  msg_info "Configuring Monica"
  cd /opt/monica || exit
  cp /opt/monica/.env.example /opt/monica/.env
  HASH_SALT=$(openssl rand -base64 32)
  sed -i \
    -e "s|^DB_USERNAME=.*|DB_USERNAME=${MARIADB_DB_USER}|" \
    -e "s|^DB_PASSWORD=.*|DB_PASSWORD=${MARIADB_DB_PASS}|" \
    -e "s|^HASH_SALT=.*|HASH_SALT=${HASH_SALT}|" \
    /opt/monica/.env
  $STD composer install --no-dev -o --no-interaction
  $STD yarn config set ignore-engines true
  $STD yarn install
  $STD yarn run production
  $STD php artisan key:generate
  $STD php artisan setup:production --email=admin@community-scripts.org --password=community-scripts.org --force
  chown -R www-data:www-data /opt/monica
  chmod -R 775 /opt/monica/storage
  echo "* * * * * root php /opt/monica/artisan schedule:run >> /dev/null 2>&1" >> /etc/crontab
  msg_ok "Configured Monica"

  msg_info "Creating Service"
  cat << EOF > /etc/apache2/sites-available/monica.conf
<VirtualHost *:80>
    ServerName monica
    DocumentRoot /opt/monica/public
    <Directory /opt/monica/public>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog /var/log/apache2/monica_error.log
    CustomLog /var/log/apache2/monica_access.log combined
</VirtualHost>
EOF
  $STD a2ensite monica
  $STD a2enmod rewrite
  $STD a2dissite 000-default.conf
  $STD systemctl reload apache2
  msg_ok "Created Service"
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
  if [[ ! -d /opt/monica ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  setup_mariadb
  NODE_VERSION="22" NODE_MODULE="yarn@latest" setup_nodejs

  if ! grep -Fq 'php /opt/monica/artisan schedule:run' /etc/crontab; then
    echo '* * * * * root php /opt/monica/artisan schedule:run >> /dev/null 2>&1' >> /etc/crontab
  fi

  if check_for_gh_release "monica" "monicahq/monica"; then
    msg_info "Stopping Service"
    systemctl stop apache2
    msg_ok "Stopped Service"

    msg_info "Creating backup"
    mv /opt/monica/ /opt/monica-backup
    msg_ok "Backup created"

    fetch_and_deploy_gh_release "monica" "monicahq/monica" "prebuild" "latest" "/opt/monica" "monica-v*.tar.bz2"

    msg_info "Configuring Monica"
    cd /opt/monica || exit
    cp -r /opt/monica-backup/.env /opt/monica
    cp -r /opt/monica-backup/storage/* /opt/monica/storage/
    $STD composer install --no-interaction --no-dev
    $STD yarn config set ignore-engines true
    $STD yarn install
    $STD yarn run production
    $STD php artisan monica:update --force
    chown -R www-data:www-data /opt/monica
    chmod -R 775 /opt/monica/storage
    rm -r /opt/monica-backup
    msg_ok "Configured Monica"

    msg_info "Starting Service"
    systemctl start apache2
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
