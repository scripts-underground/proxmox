#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/danielbrendel/hortusfox-web

# shellcheck disable=SC2034
APP="HortusFox"
var_tags="${var_tags:-plants}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  setup_mariadb
  MARIADB_DB_NAME="hortusfox" MARIADB_DB_USER="hortusfox" setup_mariadb_db
  PHP_VERSION="8.3" PHP_APACHE="YES" setup_php
  setup_composer
  fetch_and_deploy_gh_release "hortusfox" "danielbrendel/hortusfox-web" "tarball"

  msg_info "Configuring .env"
  cp /opt/hortusfox/.env.example /opt/hortusfox/.env
  sed -i "s|^DB_HOST=.*|DB_HOST=localhost|" /opt/hortusfox/.env
  sed -i "s|^DB_USER=.*|DB_USER=$MARIADB_DB_USER|" /opt/hortusfox/.env
  sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=$MARIADB_DB_PASS|" /opt/hortusfox/.env
  sed -i "s|^DB_DATABASE=.*|DB_DATABASE=$MARIADB_DB_NAME|" /opt/hortusfox/.env
  sed -i "s|^DB_ENABLE=.*|DB_ENABLE=true|" /opt/hortusfox/.env
  sed -i "s|^APP_TIMEZONE=.*|APP_TIMEZONE=Europe/Berlin|" /opt/hortusfox/.env
  msg_ok ".env configured"

  msg_info "Installing Composer dependencies"
  cd /opt/hortusfox || exit
  $STD composer install --no-dev --optimize-autoloader
  msg_ok "Composer dependencies installed"

  msg_info "Running DB migration"
  $STD php asatru migrate:fresh
  msg_ok "Migration finished"

  msg_info "Setting up HortusFox"
  $STD mariadb -u root -D "$MARIADB_DB_NAME" -e "INSERT IGNORE INTO AppModel (workspace, language, created_at) VALUES ('Default Workspace', 'en', NOW());"
  $STD php asatru plants:attributes
  $STD php asatru calendar:classes
  ADMIN_EMAIL="admin@example.com"
  ADMIN_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)"
  ADMIN_HASH=$(php -r "echo password_hash('$ADMIN_PASS', PASSWORD_BCRYPT);")
  $STD mariadb -u root -D "$MARIADB_DB_NAME" -e "INSERT IGNORE INTO UserModel (name, email, password, admin) VALUES ('Admin', '$ADMIN_EMAIL', '$ADMIN_HASH', 1);"
  cat << EOF > ~/hortusfox.creds

HortusFox-Admin-Creds:
E-Mail: $ADMIN_EMAIL
Passwort: $ADMIN_PASS
EOF
  $STD mariadb -u root -D "$MARIADB_DB_NAME" -e "INSERT IGNORE INTO LocationsModel (name, active, created_at) VALUES ('Home', 1, NOW());"
  msg_ok "Set up HortusFox"

  msg_info "Configuring Apache vHost"
  cat << EOF > /etc/apache2/sites-available/hortusfox.conf
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /opt/hortusfox/public
    <Directory /opt/hortusfox/public>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/hortusfox_error.log
    CustomLog \${APACHE_LOG_DIR}/hortusfox_access.log combined
</VirtualHost>
EOF
  chown -R www-data:www-data /opt/hortusfox
  $STD a2dissite 000-default
  $STD a2ensite hortusfox
  $STD a2enmod rewrite
  systemctl restart apache2
  msg_ok "Apache configured"
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
  if [[ ! -d /opt/hortusfox ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  setup_mariadb
  if check_for_gh_release "hortusfox" "danielbrendel/hortusfox-web"; then
    msg_info "Stopping Service"
    systemctl stop apache2
    msg_ok "Stopped Service"

    msg_info "Backing up current HortusFox installation"
    cd /opt || exit
    mv /opt/hortusfox/ /opt/hortusfox-backup
    msg_ok "Backed up current HortusFox installation"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "hortusfox" "danielbrendel/hortusfox-web" "tarball"

    msg_info "Updating HortusFox"
    cd /opt/hortusfox || exit
    cp /opt/hortusfox-backup/.env /opt/hortusfox/.env
    cp -a /opt/hortusfox-backup/public/img/. /opt/hortusfox/public/img/
    export COMPOSER_ALLOW_SUPERUSER=1
    $STD composer install --no-dev --optimize-autoloader
    $STD php asatru migrate:upgrade
    $STD php asatru plants:attributes
    $STD php asatru calendar:classes
    chown -R www-data:www-data /opt/hortusfox
    rm -r /opt/hortusfox-backup
    msg_ok "Updated HortusFox"

    msg_info "Starting Service"
    systemctl start apache2
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
