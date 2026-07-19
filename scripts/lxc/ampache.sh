#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/ampache/ampache

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Ampache"
var_tags="${var_tags:-music}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    flac \
    vorbis-tools \
    lame \
    ffmpeg \
    inotify-tools \
    libavcodec-extra \
    libmp3lame-dev \
    libtheora-dev \
    libvorbis-dev \
    libvpx-dev
  msg_ok "Installed Dependencies"

  PHP_VERSION="8.4" PHP_APACHE="YES" setup_php
  setup_mariadb
  MARIADB_DB_USER="ampache" MARIADB_DB_NAME="ampache" setup_mariadb_db

  fetch_and_deploy_gh_release "ampache" "ampache/ampache" "prebuild" "latest" "/opt/ampache" "ampache-*_all_php8.4.zip"

  msg_info "Setting Up Ampache"
  rm -rf /var/www/html
  ln -s /opt/ampache/public /var/www/html
  mv /opt/ampache/public/rest/.htaccess.dist /opt/ampache/public/rest/.htaccess
  mv /opt/ampache/public/play/.htaccess.dist /opt/ampache/public/play/.htaccess
  cp /opt/ampache/config/ampache.cfg.php.dist /opt/ampache/config/ampache.cfg.php
  chmod 664 /opt/ampache/public/rest/.htaccess /opt/ampache/public/play/.htaccess
  msg_ok "Set Up Ampache"

  msg_info "Configuring Database Connection"
  sed -i \
    -e 's|^database_hostname = .*|database_hostname = "localhost"|' \
    -e 's|^database_name = .*|database_name = "ampache"|' \
    -e 's|^database_username = .*|database_username = "ampache"|' \
    -e "s|^database_password = .*|database_password = \"${MARIADB_DB_PASS}\"|" \
    /opt/ampache/config/ampache.cfg.php
  chown -R www-data:www-data /opt/ampache
  msg_ok "Configured Database Connection"

  msg_info "Importing Database Schema"
  mariadb -u ampache -p"${MARIADB_DB_PASS}" ampache < /opt/ampache/resources/sql/ampache.sql
  msg_ok "Imported Database Schema"

  msg_info "Configuring PHP"
  sed -i \
    -e 's/upload_max_filesize = .*/upload_max_filesize = 100M/' \
    -e 's/post_max_size = .*/post_max_size = 100M/' \
    -e 's/max_execution_time = .*/max_execution_time = 600/' \
    -e 's/memory_limit = .*/memory_limit = 512M/' \
    /etc/php/8.4/apache2/php.ini
  $STD a2enmod rewrite
  $STD systemctl restart apache2
  msg_ok "Configured PHP"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}/install.php${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/ampache ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "Ampache" "ampache/ampache"; then
    msg_info "Stopping Service"
    systemctl stop apache2
    msg_ok "Stopped Service"

    msg_info "Creating Backup"
    create_backup \
      /opt/ampache/config/ampache.cfg.php \
      /opt/ampache/public/rest/.htaccess \
      /opt/ampache/public/play/.htaccess \
      /opt/ampache/advanced-config
    msg_ok "Backup Created"

    fetch_and_deploy_gh_release "Ampache" "ampache/ampache" "prebuild" "latest" "/opt/ampache" "ampache-*_all_php8.4.zip"

    restore_backup
    chmod 664 /opt/ampache/public/rest/.htaccess /opt/ampache/public/play/.htaccess
    chown -R www-data:www-data /opt/ampache

    msg_info "Starting Service"
    systemctl start apache2
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
    msg_info "Complete database update by visiting: http://${IP}/update.php"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
