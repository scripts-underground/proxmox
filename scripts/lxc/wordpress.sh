#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://wordpress.org/

APP="Wordpress"
var_tags="${var_tags:-blog;cms}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  PHP_VERSION="8.4" PHP_FPM="YES" PHP_APACHE="YES" PHP_MODULE="snmp,imap" setup_php
  setup_mariadb
  MARIADB_DB_NAME="wordpress_db" MARIADB_DB_USER="wordpress" setup_mariadb_db
  fetch_and_deploy_from_url "https://wordpress.org/latest.zip" /var/www/html/wordpress

  msg_info "Installing Wordpress (Patience)"
  chown -R www-data:www-data /var/www/html/wordpress
  cd /var/www/html/wordpress || exit
  find . -type d -exec chmod 755 {} \;
  find . -type f -exec chmod 644 {} \;
  mv wp-config-sample.php wp-config.php
  sed -i -e "s|^define( 'DB_NAME', '.*' );|define( 'DB_NAME', '$MARIADB_DB_NAME' );|" \
    -e "s|^define( 'DB_USER', '.*' );|define( 'DB_USER', '$MARIADB_DB_USER' );|" \
    -e "s|^define( 'DB_PASSWORD', '.*' );|define( 'DB_PASSWORD', '$MARIADB_DB_PASS' );|" \
    /var/www/html/wordpress/wp-config.php
  msg_ok "Installed Wordpress"

  msg_info "Setup Services"
  cat << EOF > /etc/apache2/sites-available/wordpress.conf
<VirtualHost *:80>
    ServerName yourdomain.com
    DocumentRoot /var/www/html/wordpress

    <Directory /var/www/html/wordpress>
        AllowOverride All
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined

</VirtualHost>
EOF
  $STD a2ensite wordpress.conf
  $STD a2dissite 000-default.conf
  $STD a2enmod rewrite
  systemctl reload apache2
  msg_ok "Created Services"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}/${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /var/www/html/wordpress ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  setup_mariadb
  msg_error "Wordpress should be updated via the user interface."
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
