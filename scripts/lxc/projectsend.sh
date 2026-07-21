#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: bvdberg01
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.projectsend.org/ | GitHub: https://github.com/projectsend/projectsend

APP="ProjectSend"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  PHP_VERSION="8.4" PHP_APACHE="YES" setup_php
  setup_mariadb
  MARIADB_DB_NAME="projectsend" MARIADB_DB_USER="projectsend" setup_mariadb_db
  fetch_and_deploy_gh_release "projectsend" "projectsend/projectsend" "prebuild" "latest" "/opt/projectsend" "projectsend-r*.zip"

  msg_info "Installing ProjectSend"
  mv /opt/projectsend/includes/sys.config.sample.php /opt/projectsend/includes/sys.config.php
  chown -R www-data:www-data /opt/projectsend
  chmod -R 775 /opt/projectsend
  chmod 644 /opt/projectsend/includes/sys.config.php
  sed -i -e "s/\(define('DB_NAME', \).*/\1'$MARIADB_DB_NAME');/" \
    -e "s/\(define('DB_USER', \).*/\1'$MARIADB_DB_USER');/" \
    -e "s/\(define('DB_PASSWORD', \).*/\1'$MARIADB_DB_PASS');/" \
    /opt/projectsend/includes/sys.config.php
  sed -i -e "s/^\(memory_limit = \).*/\1 256M/" \
    -e "s/^\(post_max_size = \).*/\1 256M/" \
    -e "s/^\(upload_max_filesize = \).*/\1 256M/" \
    -e "s/^\(max_execution_time = \).*/\1 300/" \
    /etc/php/8.4/apache2/php.ini
  msg_ok "Installed projectsend"

  msg_info "Creating Service"
  cat << EOF > /etc/apache2/sites-available/projectsend.conf
<VirtualHost *:80>
    ServerName projectsend
    DocumentRoot /opt/projectsend
    <Directory /opt/projectsend>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog /var/log/apache2/projectsend_error.log
    CustomLog /var/log/apache2/projectsend_access.log combined
</VirtualHost>
EOF
  $STD a2ensite projectsend
  $STD a2enmod rewrite
  $STD a2dissite 000-default.conf
  $STD systemctl reload apache2
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}/install for the initial setup${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/projectsend ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  setup_mariadb

  if check_for_gh_release "projectsend" "projectsend/projectsend"; then
    msg_info "Stopping Service"
    systemctl stop apache2
    msg_ok "Stopped Service"

    php_ver=$(php -v | head -n 1 | awk '{print $2}')
    if [[ ! $php_ver == "8.4"* ]]; then
      PHP_VERSION="8.4" PHP_APACHE="YES" setup_php
    fi

    mv /opt/projectsend/includes/sys.config.php /opt/sys.config.php
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "projectsend" "projectsend/projectsend" "prebuild" "latest" "/opt/projectsend" "projectsend-r*.zip"
    mv /opt/sys.config.php /opt/projectsend/includes/sys.config.php
    chown -R www-data:www-data /opt/projectsend
    chmod -R 775 /opt/projectsend

    msg_info "Starting Service"
    systemctl start apache2
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
