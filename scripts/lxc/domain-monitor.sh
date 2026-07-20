#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Hosteroid/domain-monitor

# shellcheck disable=SC2034
APP="Domain-Monitor"
var_tags="${var_tags:-proxy}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y --no-install-recommends \
    libicu-dev \
    libzip-dev \
    libpng-dev \
    libjpeg62-turbo-dev \
    libfreetype6-dev \
    libxml2-dev \
    libcurl4-openssl-dev \
    libonig-dev \
    pkg-config
  msg_ok "Installed Dependencies"

  PHP_VERSION="8.4" PHP_APACHE="YES" PHP_FPM="YES" setup_php
  setup_composer
  setup_mariadb
  MARIADB_DB_NAME="domain_monitor" MARIADB_DB_USER="domainmonitor" setup_mariadb_db
  fetch_and_deploy_gh_release "domain-monitor" "Hosteroid/domain-monitor" "prebuild" "latest" "/opt/domain-monitor" "domain-monitor-v*.zip"

  msg_info "Setting up Domain Monitor"
  ENC_KEY=$(openssl rand -base64 32 | tr -d '\n')
  cd /opt/domain-monitor || exit
  $STD composer install
  cp env.example.txt .env
  sed -i -e "s|^APP_ENV=.*|APP_ENV=production|" \
    -e "s|^APP_ENCRYPTION_KEY=.*|APP_ENCRYPTION_KEY=$ENC_KEY|" \
    -e "s|^SESSION_COOKIE_HTTPONLY=.*|SESSION_COOKIE_HTTPONLY=0|" \
    -e "s|^DB_USERNAME=.*|DB_USERNAME=$MARIADB_DB_USER|" \
    -e "s|^DB_PASSWORD=.*|DB_PASSWORD=$MARIADB_DB_PASS|" \
    -e "s|^DB_DATABASE=.*|DB_DATABASE=$MARIADB_DB_NAME|" .env
  echo "0 0 * * * www-data /usr/bin/php /opt/domain-monitor/cron/check_domains.php" >> /etc/crontab
  cat << EOF > /etc/apache2/sites-enabled/000-default.conf
<VirtualHost *:80>
    ServerName domainmonitor.local
    DocumentRoot "/opt/domain-monitor/public"

    <Directory "/opt/domain-monitor/public">
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
  chown -R www-data:www-data /opt/domain-monitor
  $STD a2enmod rewrite headers
  $STD systemctl reload apache2
  msg_ok "Setup Domain Monitor"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/domain-monitor ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  setup_mariadb

  if grep -Fq "root /usr/bin/php /opt/domain-monitor/cron/check_domains.php" /etc/crontab; then
    sed -i 's|root /usr/bin/php /opt/domain-monitor/cron/check_domains.php|www-data /usr/bin/php /opt/domain-monitor/cron/check_domains.php|' /etc/crontab
  fi

  if ! grep -Fq "www-data /usr/bin/php /opt/domain-monitor/cron/check_domains.php" /etc/crontab; then
    echo "0 0 * * * www-data /usr/bin/php /opt/domain-monitor/cron/check_domains.php" >> /etc/crontab
  fi

  if check_for_gh_release "domain-monitor" "Hosteroid/domain-monitor"; then
    msg_info "Stopping Service"
    systemctl stop apache2
    msg_info "Service stopped"

    create_backup /opt/domain-monitor/.env

    setup_composer
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "domain-monitor" "Hosteroid/domain-monitor" "prebuild" "latest" "/opt/domain-monitor" "domain-monitor-v*.zip"

    msg_info "Updating Domain Monitor"
    cd /opt/domain-monitor || exit
    $STD composer install
    chown -R www-data:www-data /opt/domain-monitor
    msg_ok "Updated Domain Monitor"

    restore_backup

    msg_info "Restarting Services"
    systemctl start apache2
    msg_ok "Restarted Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
