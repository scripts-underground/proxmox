#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Stroopwafe1
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://leantime.io

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Leantime"
var_tags="${var_tags:-productivity}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y apache2
  msg_ok "Installed Dependencies"

  export PHP_VERSION="8.4"
  PHP_APACHE="YES" PHP_FPM="YES" setup_php
  setup_mariadb
  MARIADB_DB_NAME="leantime" MARIADB_DB_USER="leantime" setup_mariadb_db

  fetch_and_deploy_gh_release "leantime" "Leantime/leantime" "prebuild" "latest" "/opt/leantime" "Leantime*.tar.gz"

  msg_info "Setup Leantime"
  chown -R www-data:www-data /opt/leantime
  chmod -R 750 /opt/leantime
  cat << EOF > /etc/apache2/sites-enabled/000-default.conf
<VirtualHost *:80>
  ServerAdmin webmaster@localhost
  DocumentRoot /opt/leantime/public
  DirectoryIndex index.php index.html index.cgi index.pl index.xhtml
  Options +ExecCGI

  <Directory /opt/leantime/>
    Options FollowSymLinks
    Require all granted
    AllowOverride All
  </Directory>

  <Location />
    Require all granted
  </Location>

  ErrorLog /var/log/apache2/error.log
  CustomLog /var/log/apache2/access.log combined
</VirtualHost>
EOF
  mv /opt/leantime/config/sample.env /opt/leantime/config/.env
  LEAN_SESSION_PASSWORD="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)"
  sed -i \
    -e "s|^LEAN_DB_DATABASE.*|LEAN_DB_DATABASE = '$MARIADB_DB_NAME'|" \
    -e "s|^LEAN_DB_USER.*|LEAN_DB_USER = '$MARIADB_DB_USER'|" \
    -e "s|^LEAN_DB_PASSWORD.*|LEAN_DB_PASSWORD = '$MARIADB_DB_PASS'|" \
    -e "s|^LEAN_SESSION_PASSWORD.*|LEAN_SESSION_PASSWORD = '$LEAN_SESSION_PASSWORD'|" \
    /opt/leantime/config/.env
  $STD a2enmod -q proxy_fcgi setenvif rewrite
  $STD a2enconf -q "php8.4-fpm"
  sed -i \
    -e "s/^;extension.\(curl\|fileinfo\|gd\|intl\|ldap\|mbstring\|exif\|mysqli\|odbc\|openssl\|pdo_mysql\)/extension=\1/g" \
    "/etc/php/8.4/apache2/php.ini"
  systemctl restart apache2
  msg_ok "Setup Leantime"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}/install${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/leantime ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  setup_mariadb
  if check_for_gh_release "leantime" "Leantime/leantime"; then
    msg_info "Creating Backup"
    mariadb-dump leantime > "/opt/leantime_db_backup_$(date +%F).sql"
    tar -czf "/opt/leantime_backup_$(date +%F).tar.gz" /opt/leantime
    mv /opt/leantime /opt/leantime_bak
    msg_ok "Backup Created"

    fetch_and_deploy_gh_release "leantime" "Leantime/leantime" "prebuild" "latest" "/opt/leantime" "Leantime*.tar.gz"

    msg_info "Restoring Config & Permissions"
    mv /opt/leantime_bak/config/.env /opt/leantime/config/.env
    chown -R www-data:www-data /opt/leantime
    chmod -R 750 /opt/leantime
    msg_ok "Restored Config & Permissions"

    msg_info "Removing Backup"
    rm -rf /opt/leantime_bak
    msg_ok "Removed Backup"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
