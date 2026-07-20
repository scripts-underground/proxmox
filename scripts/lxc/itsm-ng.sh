#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Florianb63
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://itsm-ng.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="ITSM-NG"
var_tags="${var_tags:-asset-management;foss}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  setup_mariadb

  msg_info "Loading timezone data"
  $STD mariadb-tzinfo-to-sql /usr/share/zoneinfo | $STD mariadb mysql
  msg_ok "Loaded timezone data"

  MARIADB_DB_NAME="itsmng_db" MARIADB_DB_USER="itsmng" MARIADB_DB_EXTRA_GRANTS="GRANT SELECT ON \`mysql\`.\`time_zone_name\`" setup_mariadb_db

  msg_info "Installing ITSM-NG"
  setup_deb822_repo \
    "itsm-ng" \
    "http://deb.itsm-ng.org/pubkey.gpg" \
    "http://deb.itsm-ng.org/$(get_os_info id)/" \
    "$(get_os_info codename)"
  $STD apt install -y itsm-ng
  cd /usr/share/itsm-ng || exit
  $STD php bin/console db:install \
    --db-name="$MARIADB_DB_NAME" \
    --db-user="$MARIADB_DB_USER" \
    --db-password="$MARIADB_DB_PASS" \
    --no-interaction
  $STD a2dissite 000-default.conf
  echo "* * * * * www-data php /usr/share/itsm-ng/front/cron.php" | crontab -
  msg_ok "Installed ITSM-NG"

  msg_info "Setting permissions"
  chown -R www-data:www-data /var/lib/itsm-ng
  mkdir -p /usr/share/itsm-ng/css/palettes
  chown -R www-data:www-data /usr/share/itsm-ng/css
  chown -R www-data:www-data /usr/share/itsm-ng/css_compiled
  chown www-data:www-data /etc/itsm-ng/config_db.php
  msg_ok "Set permissions"

  msg_info "Configuring PHP"
  PHP_VERSION=$(basename "$(find /etc/php/ -maxdepth 1 -type d -name '[0-9]*.[0-9]*' | head -n 1)")
  PHP_INI="/etc/php/$PHP_VERSION/apache2/php.ini"
  sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 20M/' $PHP_INI
  sed -i 's/^post_max_size = .*/post_max_size = 20M/' $PHP_INI
  sed -i 's/^max_execution_time = .*/max_execution_time = 60/' $PHP_INI
  sed -i 's/^[;]*max_input_vars *=.*/max_input_vars = 5000/' "$PHP_INI"
  sed -i 's/^memory_limit = .*/memory_limit = 256M/' $PHP_INI
  sed -i 's/^;\?\s*session.cookie_httponly\s*=.*/session.cookie_httponly = On/' $PHP_INI
  systemctl restart apache2
  rm -rf /usr/share/itsm-ng/install
  msg_ok "Configured PHP"
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

  if [[ ! -f /etc/itsm-ng/config_db.php ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ITSM-NG"
  $STD apt update
  $STD apt -y upgrade
  chown -R www-data:www-data /var/lib/itsm-ng
  mkdir -p /usr/share/itsm-ng/css/palettes
  chown -R www-data:www-data /usr/share/itsm-ng/css
  chown -R www-data:www-data /usr/share/itsm-ng/css_compiled
  chown www-data:www-data /etc/itsm-ng/config_db.php
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
