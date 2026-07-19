#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: bvdberg01
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://sabre.io/baikal/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Baikal"
var_tags="${var_tags:-Dav}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git
  msg_ok "Installed Dependencies"

  PG_VERSION="16" setup_postgresql
  PHP_APACHE="YES" PHP_VERSION="8.3" setup_php
  setup_composer
  fetch_and_deploy_gh_release "baikal" "sabre-io/Baikal" "tarball"
  PG_DB_NAME="baikal_db" PG_DB_USER="baikal_user" PG_DB_PASS="$(openssl rand -base64 12)" setup_postgresql_db

  msg_info "Configuring Baikal"
  cd /opt/baikal || exit
  $STD composer install
  cat << EOF > /opt/baikal/config/baikal.yaml
database:
    backend: pgsql
    pgsql_host: localhost
    pgsql_dbname: $PG_DB_NAME
    pgsql_username: $PG_DB_USER
    pgsql_password: $PG_DB_PASS
EOF
  chown -R www-data:www-data /opt/baikal/
  chmod -R 755 /opt/baikal/
  msg_ok "Configured Baikal"

  msg_info "Creating Service"
  cat << EOF > /etc/apache2/sites-available/baikal.conf
<VirtualHost *:80>
    ServerName baikal
    DocumentRoot /opt/baikal/html

    RewriteEngine on
    RewriteRule /.well-known/carddav /dav.php [R=308,L]
    RewriteRule /.well-known/caldav  /dav.php [R=308,L]
    RewriteCond %{REQUEST_URI} ^/dav.php$ [NC]
    RewriteRule ^(.*)$ /dav.php/ [R=301,L]
        
    <Directory /opt/baikal/html>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <IfModule mod_expires.c>
        ExpiresActive Off
    </IfModule>

    ErrorLog /var/log/apache2/baikal_error.log
    CustomLog /var/log/apache2/baikal_access.log combined
</VirtualHost>
EOF
  $STD a2ensite baikal
  $STD a2enmod rewrite
  $STD a2dissite 000-default.conf
  $STD systemctl reload apache2
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/baikal ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "baikal" "sabre-io/Baikal"; then
    msg_info "Stopping Service"
    systemctl stop apache2
    msg_ok "Stopped Service"

    create_backup /opt/baikal/config/baikal.yaml \
      /opt/baikal/Specific/

    PHP_APACHE="YES" PHP_VERSION="8.3" setup_php
    setup_composer
    fetch_and_deploy_gh_release "baikal" "sabre-io/Baikal" "tarball"
    restore_backup
    chown -R www-data:www-data /opt/baikal/
    chmod -R 755 /opt/baikal/

    msg_info "Configuring Baikal"
    cd /opt/baikal || exit
    $STD composer install
    msg_ok "Configured Baikal"

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
