#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: sudofly
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://webtrees.net/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Webtrees"
var_tags="${var_tags:-genealogy;cms}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    caddy \
    unzip
  msg_ok "Installed Dependencies"

  PHP_VERSION="8.3" PHP_FPM="YES" PHP_MODULES="bcmath,gd,intl,xml,zip,pdo_mysql,mbstring,curl" setup_php
  setup_mariadb
  MARIADB_DB_NAME="webtrees" MARIADB_DB_USER="webtrees" setup_mariadb_db
  $STD mariadb -u root -e "GRANT ALL ON \`webtrees\`.* TO 'webtrees'@'127.0.0.1' IDENTIFIED BY '${MARIADB_DB_PASS}'; FLUSH PRIVILEGES;"

  fetch_and_deploy_gh_release "webtrees" "fisharebest/webtrees" "prebuild" "latest" "/opt/webtrees" "webtrees-*.zip"

  msg_info "Setting up Webtrees"
  chown -R www-data:www-data /opt/webtrees
  msg_ok "Set up Webtrees"

  msg_info "Configuring Caddy"
  PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
  cat << EOF > /etc/caddy/Caddyfile
:80 {
    root * /opt/webtrees
    php_fastcgi unix//run/php/php${PHP_VER}-fpm.sock
    file_server
    encode gzip
}
EOF
  usermod -aG www-data caddy
  systemctl enable -q --now php${PHP_VER}-fpm
  systemctl restart caddy
  msg_ok "Configured Caddy"

  msg_info "Automating Webtrees Setup"
  mkdir -p /opt/webtrees/data
  chown -R www-data:www-data /opt/webtrees/data
  WT_ADMIN_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c15)
  su -s /bin/bash www-data -c "php /opt/webtrees/index.php config-ini \
    --dbhost=127.0.0.1 \
    --dbport=3306 \
    --dbuser=webtrees \
    --dbpass=\"${MARIADB_DB_PASS}\" \
    --dbname=webtrees \
    --tblpfx=wt_ \
    --base-url=\"http://${LOCAL_IP}\""
  msg_info "Initializing Webtrees database schema"
  # shellcheck disable=SC2034
  for i in {1..15}; do
    if curl -sf "http://127.0.0.1/" > /dev/null 2>&1; then
      break
    fi
    sleep 2
  done
  $STD mariadb -u webtrees -p"${MARIADB_DB_PASS}" -h 127.0.0.1 webtrees -e "SHOW TABLES LIKE 'wt_user';" | grep -q wt_user
  msg_ok "Initialized Webtrees database schema"
  su -s /bin/bash www-data -c "php /opt/webtrees/index.php user Admin \
    --create \
    --real-name=\"Administrator\" \
    --email=\"admin@example.com\" \
    --password=\"${WT_ADMIN_PASS}\""
  su -s /bin/bash www-data -c "php /opt/webtrees/index.php user-setting Admin canadmin 1"

  cat << EOF > ~/webtrees.creds
Webtrees Admin User: Admin
Webtrees Admin Password: ${WT_ADMIN_PASS}
EOF
  msg_ok "Webtrees Setup Automated"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
  echo -e "${INFO}${YW} Admin credentials are stored in ~/webtrees.creds${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/webtrees ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "webtrees" "fisharebest/webtrees"; then
    msg_info "Stopping Service"
    PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
    systemctl stop caddy php${PHP_VER}-fpm
    msg_ok "Stopped Service"

    create_backup /opt/webtrees/data

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "webtrees" "fisharebest/webtrees" "prebuild" "latest" "/opt/webtrees" "webtrees-*.zip"

    restore_backup
    chown -R www-data:www-data /opt/webtrees

    msg_info "Starting Service"
    systemctl start caddy php${PHP_VER}-fpm
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
