#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://matomo.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Matomo"
var_tags="${var_tags:-analytics;tracking;privacy}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    caddy \
    unzip \
    build-essential
  msg_ok "Installed Dependencies"

  PHP_VERSION="8.4" PHP_FPM="YES" PHP_MODULE="gd,mysqli,pdo_mysql,curl,xml,mbstring,intl,bcmath,zip" setup_php
  setup_composer
  setup_mariadb
  MARIADB_DB_NAME="matomo" MARIADB_DB_USER="matomo" setup_mariadb_db

  fetch_and_deploy_gh_release "matomo" "matomo-org/matomo" "prebuild" "latest" "/opt/matomo" "matomo-*.zip"

  msg_info "Setting up Matomo"
  if [[ -d /opt/matomo/matomo ]]; then
    find /opt/matomo/matomo -mindepth 1 -maxdepth 1 -exec mv -t /opt/matomo {} +
    rm -rf /opt/matomo/matomo
  fi
  mkdir -p /opt/matomo/tmp
  chmod -R 755 /opt/matomo/tmp
  cat << EOF > /opt/matomo/config/config.ini.php
; Matomo configuration file
; Auto-generated during setup

[General]
trusted_hosts[] = "\${LOCAL_IP}"

[database]
host = "127.0.0.1"
username = "${MARIADB_DB_USER}"
password = "${MARIADB_DB_PASS}"
dbname = "${MARIADB_DB_NAME}"
tables_prefix = "matomo_"
adapter = "Mysql\PDO\Mysql"
type = "InnoDB"
schema = "Mysql"
port = 3306
EOF
  cat << EOF > /opt/matomo/config/matomo.creds
Matomo Database User: ${MARIADB_DB_USER}
Matomo Database Password: ${MARIADB_DB_PASS}
Matomo Database Name: ${MARIADB_DB_NAME}
EOF
  chown -R www-data:www-data /opt/matomo
  msg_ok "Set up Matomo"

  msg_info "Configuring Caddy"
  PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
  cat << EOF > /etc/caddy/Caddyfile
:80 {
    root * /opt/matomo
    php_fastcgi unix//run/php/php${PHP_VER}-fpm.sock
    file_server
    encode gzip
    redir / /index.php
}
EOF
  usermod -aG www-data caddy
  msg_ok "Configured Caddy"

  systemctl enable -q --now php${PHP_VER}-fpm
  systemctl reload caddy
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/matomo ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "matomo" "matomo-org/matomo"; then
    msg_info "Stopping Services"
    systemctl stop caddy
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    [[ -f /opt/matomo/config/config.ini.php ]] && cp /opt/matomo/config/config.ini.php /opt/matomo_config.bak
    [[ -d /opt/matomo/misc/user ]] && cp -r /opt/matomo/misc/user /opt/matomo_user_backup
    [[ -f /opt/matomo/config/matomo.creds ]] && cp /opt/matomo/config/matomo.creds /opt/matomo_db_creds.bak
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "matomo" "matomo-org/matomo" "prebuild" "latest" "/opt/matomo" "matomo-*.zip"

    msg_info "Setting up Matomo"
    if [[ -d /opt/matomo/matomo ]]; then
      rm -rf /opt/matomo/tmp "/opt/matomo/How to install Matomo.html"
      find /opt/matomo/matomo -mindepth 1 -maxdepth 1 -exec mv -t /opt/matomo {} +
      rm -rf /opt/matomo/matomo
    fi
    mkdir -p /opt/matomo/tmp
    chmod -R 755 /opt/matomo/tmp
    msg_ok "Set up Matomo"

    msg_info "Restoring Data"
    if [[ -f /opt/matomo_config.bak ]]; then
      mkdir -p /opt/matomo/config
      cp /opt/matomo_config.bak /opt/matomo/config/config.ini.php
    fi
    if [[ -d /opt/matomo_user_backup ]]; then
      mkdir -p /opt/matomo/misc/user
      cp -r /opt/matomo_user_backup/. /opt/matomo/misc/user
    fi
    [[ -f /opt/matomo_db_creds.bak ]] && cp /opt/matomo_db_creds.bak /opt/matomo/config/matomo.creds
    rm -f /opt/matomo_config.bak /opt/matomo_db_creds.bak
    rm -rf /opt/matomo_user_backup
    chown -R www-data:www-data /opt/matomo
    msg_ok "Restored Data"

    if [[ -f /opt/matomo/console ]]; then
      msg_info "Running Matomo database upgrade"
      cd /opt/matomo || exit
      $STD runuser -u www-data -- php console core:update --no-interaction
      msg_ok "Ran Matomo database upgrade"
    fi

    msg_info "Starting Services"
    PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
    systemctl restart "php${PHP_VER}-fpm"
    systemctl start caddy
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
