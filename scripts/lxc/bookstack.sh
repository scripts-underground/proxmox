#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.bookstackapp.com/

APP="Bookstack"
var_tags="${var_tags:-organizer}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    make \
    git
  msg_ok "Installed Dependencies"

  PHP_VERSION="8.3" PHP_APACHE="YES" PHP_FPM="YES" PHP_MODULE="ldap,tidy,mysqli" setup_php
  setup_composer
  setup_mariadb
  MARIADB_DB_NAME="bookstack_db" MARIADB_DB_USER="bookstack_user" setup_mariadb_db

  fetch_and_deploy_gh_release "bookstack" "BookStackApp/BookStack" "tarball"

  msg_info "Configuring Bookstack"
  cd /opt/bookstack || exit
  cp .env.example .env
  sed -i "s|APP_URL=.*|APP_URL=http://$LOCAL_IP|g" /opt/bookstack/.env
  sed -i "s/DB_DATABASE=.*/DB_DATABASE=$MARIADB_DB_NAME/" /opt/bookstack/.env
  sed -i "s/DB_USERNAME=.*/DB_USERNAME=$MARIADB_DB_USER/" /opt/bookstack/.env
  sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$MARIADB_DB_PASS/" /opt/bookstack/.env
  $STD composer install --no-dev --no-plugins --no-interaction
  $STD php artisan key:generate --no-interaction --force
  $STD php artisan migrate --no-interaction --force
  chown www-data:www-data -R /opt/bookstack /opt/bookstack/bootstrap/cache /opt/bookstack/public/uploads /opt/bookstack/storage
  chmod -R 755 /opt/bookstack /opt/bookstack/bootstrap/cache /opt/bookstack/public/uploads /opt/bookstack/storage
  chmod -R 775 /opt/bookstack/storage /opt/bookstack/bootstrap/cache /opt/bookstack/public/uploads
  chmod -R 640 /opt/bookstack/.env
  $STD a2enmod rewrite
  $STD a2enmod php8.3
  msg_ok "Configured Bookstack"

  msg_info "Creating Service"
  cat << EOF > /etc/apache2/sites-available/bookstack.conf
<VirtualHost *:80>
  ServerAdmin webmaster@localhost
  DocumentRoot /opt/bookstack/public/

  <Directory /opt/bookstack/public/>
      Options -Indexes +FollowSymLinks
      AllowOverride None
      Require all granted
      <IfModule mod_rewrite.c>
          <IfModule mod_negotiation.c>
              Options -MultiViews -Indexes
          </IfModule>

          RewriteEngine On

          # Handle Authorization Header
          RewriteCond %{HTTP:Authorization} .
          RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]

          # Redirect Trailing Slashes If Not A Folder...
          RewriteCond %{REQUEST_FILENAME} !-d
          RewriteCond %{REQUEST_URI} (.+)/$
          RewriteRule ^ %1 [L,R=301]

          # Handle Front Controller...
          RewriteCond %{REQUEST_FILENAME} !-d
          RewriteCond %{REQUEST_FILENAME} !-f
          RewriteRule ^ index.php [L]
      </IfModule>
  </Directory>

    ErrorLog /var/log/apache2/error.log
    CustomLog /var/log/apache2/access.log combined

</VirtualHost>
EOF
  $STD a2ensite bookstack.conf
  $STD a2dissite 000-default.conf
  $STD systemctl reload apache2
  msg_ok "Created Services"
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

  if [[ ! -d /opt/bookstack ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  setup_mariadb
  ensure_dependencies git
  if check_for_gh_release "bookstack" "BookStackApp/BookStack"; then
    msg_info "Stopping Apache2"
    systemctl stop apache2
    msg_ok "Services Stopped"

    create_backup /opt/bookstack/.env \
      /opt/bookstack/public/uploads \
      /opt/bookstack/storage/uploads \
      /opt/bookstack/themes
    fetch_and_deploy_gh_release "bookstack" "BookStackApp/BookStack" "tarball"
    PHP_VERSION="8.3" PHP_APACHE="YES" PHP_FPM="YES" PHP_MODULE="ldap,tidy,mysqli" setup_php
    setup_composer
    restore_backup

    msg_info "Configuring BookStack"
    cd /opt/bookstack || exit
    export COMPOSER_ALLOW_SUPERUSER=1
    $STD /usr/local/bin/composer install --no-dev
    $STD php artisan migrate --force
    chown www-data:www-data -R /opt/bookstack /opt/bookstack/bootstrap/cache /opt/bookstack/public/uploads /opt/bookstack/storage
    chmod -R 755 /opt/bookstack /opt/bookstack/bootstrap/cache /opt/bookstack/public/uploads /opt/bookstack/storage
    chmod -R 775 /opt/bookstack/storage /opt/bookstack/bootstrap/cache /opt/bookstack/public/uploads
    chmod -R 640 /opt/bookstack/.env
    msg_ok "Configured BookStack"

    msg_info "Starting Apache2"
    systemctl start apache2
    msg_ok "Started Apache2"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
