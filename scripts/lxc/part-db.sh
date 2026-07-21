#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: bvdberg01
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://docs.part-db.de/ | Github: https://github.com/Part-DB/Part-DB-server

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Part-DB"
var_tags="${var_tags:-inventory;parts}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="partdb" PG_DB_USER="partdb" setup_postgresql_db
  PHP_VERSION="8.4" PHP_APACHE="YES" PHP_MODULE="xsl" PHP_POST_MAX_SIZE="100M" PHP_UPLOAD_MAX_FILESIZE="100M" setup_php
  setup_composer

  fetch_and_deploy_gh_release "partdb" "Part-DB/Part-DB-server" "prebuild" "latest" "/opt/partdb" "partdb_with_assets.zip"

  msg_info "Installing Part-DB"
  cd /opt/partdb || exit
  cp .env .env.local
  sed -i "s|DATABASE_URL=\"sqlite:///%kernel.project_dir%/var/app.db\"|DATABASE_URL=\"postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}?serverVersion=12.19&charset=utf8\"|" .env.local
  export COMPOSER_ALLOW_SUPERUSER=1
  $STD composer install --no-dev -o --no-interaction
  $STD php bin/console cache:clear
  php bin/console doctrine:migrations:migrate -n > ~/database-migration-output
  chown -R www-data:www-data /opt/partdb
  ADMIN_PASS=$(grep -oP 'The initial password for the "admin" user is: \K\w+' ~/database-migration-output)
  cat << EOF > ~/partdb.creds

Part-DB Admin User: admin
Part-DB Admin Password: $ADMIN_PASS
EOF
  rm -rf ~/database-migration-output
  msg_ok "Installed Part-DB"

  msg_info "Creating Service"
  cat << EOF > /etc/apache2/sites-available/partdb.conf
<VirtualHost *:80>
    ServerName partdb
    DocumentRoot /opt/partdb/public
    <Directory /opt/partdb/public>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog /var/log/apache2/partdb_error.log
    CustomLog /var/log/apache2/partdb_access.log combined
</VirtualHost>
EOF
  $STD a2ensite partdb
  $STD a2enmod rewrite
  $STD a2dissite 000-default.conf
  $STD systemctl reload apache2
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
  echo -e "${INFO}${YW}Credentials are saved in ~/partdb.creds${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/partdb ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  setup_composer

  if check_for_gh_release "partdb" "Part-DB/Part-DB-server"; then
    msg_info "Stopping Service"
    systemctl stop apache2
    msg_ok "Stopped Service"

    mv /opt/partdb/ /opt/partdb-backup
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "partdb" "Part-DB/Part-DB-server" "prebuild" "latest" "/opt/partdb" "partdb_with_assets.zip"

    msg_info "Updating Part-DB"
    cd /opt/partdb/ || exit
    cp -r /opt/partdb-backup/.env.local /opt/partdb/
    cp -r /opt/partdb-backup/public/media /opt/partdb/public/
    cp -r /opt/partdb-backup/config/banner.md /opt/partdb/config/
    export COMPOSER_ALLOW_SUPERUSER=1
    $STD composer install --no-dev -o --no-interaction
    $STD php bin/console cache:clear
    $STD php bin/console doctrine:migrations:migrate -n
    chown -R www-data:www-data /opt/partdb
    rm -r /opt/partdb-backup
    msg_ok "Updated Part-DB"

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
