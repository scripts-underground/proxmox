#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Nícolas Pastorello (opastorello)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.glpi-project.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="GLPI"
var_tags="${var_tags:-asset-management;foss}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    git \
    apache2 \
    php8.4-{apcu,cli,common,curl,gd,ldap,mysql,xmlrpc,xml,mbstring,bcmath,intl,zip,redis,bz2,soap} \
    php-cas \
    libapache2-mod-php
  msg_ok "Installed Dependencies"

  setup_mariadb

  msg_info "Setting up Database"
  MARIADB_DB_NAME="glpi_db" MARIADB_DB_USER="glpi" MARIADB_DB_EXTRA_GRANTS="GRANT SELECT ON \`mysql\`.\`time_zone_name\`" setup_mariadb_db
  $STD mariadb-tzinfo-to-sql /usr/share/zoneinfo | $STD mariadb mysql
  msg_ok "Set up Database"

  msg_info "Installing GLPI"
  RELEASE=$(get_latest_github_release "glpi-project/glpi")
  fetch_and_deploy_gh_release "glpi" "glpi-project/glpi" "prebuild" "latest" "/opt/glpi" "glpi-*.tgz"
  echo "${RELEASE}" > /opt/${APP}_version.txt
  msg_ok "Installed GLPI"

  msg_info "Configuring Downstream file"
  cat << EOF > /opt/glpi/inc/downstream.php
<?php
define('GLPI_CONFIG_DIR', '/etc/glpi/');
if (file_exists(GLPI_CONFIG_DIR . '/local_define.php')) {
    require_once GLPI_CONFIG_DIR . '/local_define.php';
}
EOF

  mv /opt/glpi/config /etc/glpi
  mv /opt/glpi/files /var/lib/glpi
  mv /var/lib/glpi/_log /var/log/glpi

  cat << EOF > /etc/glpi/local_define.php
<?php
define('GLPI_VAR_DIR', '/var/lib/glpi');
define('GLPI_DOC_DIR', GLPI_VAR_DIR);
define('GLPI_CRON_DIR', GLPI_VAR_DIR . '/_cron');
define('GLPI_DUMP_DIR', GLPI_VAR_DIR . '/_dumps');
define('GLPI_GRAPH_DIR', GLPI_VAR_DIR . '/_graphs');
define('GLPI_LOCK_DIR', GLPI_VAR_DIR . '/_lock');
define('GLPI_PICTURE_DIR', GLPI_VAR_DIR . '/_pictures');
define('GLPI_PLUGIN_DOC_DIR', GLPI_VAR_DIR . '/_plugins');
define('GLPI_RSS_DIR', GLPI_VAR_DIR . '/_rss');
define('GLPI_SESSION_DIR', GLPI_VAR_DIR . '/_sessions');
define('GLPI_TMP_DIR', GLPI_VAR_DIR . '/_tmp');
define('GLPI_UPLOAD_DIR', GLPI_VAR_DIR . '/_uploads');
define('GLPI_CACHE_DIR', GLPI_VAR_DIR . '/_cache');
define('GLPI_LOG_DIR', '/var/log/glpi');
EOF
  msg_ok "Configured Downstream file"

  msg_info "Configuring GLPI Database"
  $STD /usr/bin/php /opt/glpi/bin/console db:install \
    --db-host=localhost \
    --db-name="${MARIADB_DB_NAME}" \
    --db-user="${MARIADB_DB_USER}" \
    --db-password="${MARIADB_DB_PASS}" \
    --default-language=en_US \
    --no-interaction \
    --allow-superuser \
    --force
  msg_ok "Configured GLPI Database"

  msg_info "Setting Folder and File Permissions"
  chown root:root /opt/glpi -R
  chown www-data:www-data /etc/glpi -R
  chown www-data:www-data /var/lib/glpi -R
  chown www-data:www-data /var/log/glpi -R
  chown www-data:www-data /opt/glpi/marketplace -Rf
  find /opt/glpi -type f -exec chmod 0644 {} \;
  find /opt/glpi -type d -exec chmod 0755 {} \;
  find /etc/glpi -type f -exec chmod 0644 {} \;
  find /etc/glpi -type d -exec chmod 0755 {} \;
  find /var/lib/glpi -type f -exec chmod 0644 {} \;
  find /var/lib/glpi -type d -exec chmod 0755 {} \;
  find /var/log/glpi -type f -exec chmod 0644 {} \;
  find /var/log/glpi -type d -exec chmod 0755 {} \;
  msg_ok "Set Folder and File Permissions"

  msg_info "Setting up Apache"
  cat << EOF > /etc/apache2/sites-available/glpi.conf
<VirtualHost *:80>
    ServerName localhost
    DocumentRoot /opt/glpi/public

    <Directory /opt/glpi/public>
        Require all granted
        RewriteEngine On
        RewriteCond %{HTTP:Authorization} ^(.+)$
        RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteRule ^(.*)$ index.php [QSA,L]
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/glpi_error.log
    CustomLog \${APACHE_LOG_DIR}/glpi_access.log combined
</VirtualHost>
EOF
  $STD a2dissite 000-default.conf
  $STD a2enmod rewrite
  $STD a2ensite glpi.conf
  rm -rf /opt/glpi/install/install.php
  msg_ok "Set up Apache"

  msg_info "Setting up Cronjob"
  echo "* * * * * php /opt/glpi/front/cron.php" | crontab -u www-data -
  msg_ok "Set up Cronjob"

  msg_info "Updating PHP Params"
  PHP_VERSION=$(basename "$(find /etc/php/ -maxdepth 1 -type d -name '[0-9]*.[0-9]*' | head -n 1)")
  PHP_INI="/etc/php/$PHP_VERSION/apache2/php.ini"
  sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 20M/' $PHP_INI
  sed -i 's/^post_max_size = .*/post_max_size = 20M/' $PHP_INI
  sed -i 's/^max_execution_time = .*/max_execution_time = 60/' $PHP_INI
  sed -i 's/^max_input_vars = .*/max_input_vars = 5000/' $PHP_INI
  sed -i 's/^memory_limit = .*/memory_limit = 256M/' $PHP_INI
  sed -i 's/^;\?\s*session.cookie_httponly\s*=.*/session.cookie_httponly = On/' $PHP_INI
  systemctl restart apache2
  msg_ok "Updated PHP Params"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:80${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/glpi ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(get_latest_github_release "glpi-project/glpi")
  if [[ -f /opt/${APP}_version.txt ]] && [[ "${RELEASE}" == "$(cat /opt/${APP}_version.txt)" ]]; then
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
  else
    msg_error "Currently we don't provide an update function for ${APP}."
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
