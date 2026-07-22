#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/TasmoAdmin/TasmoAdmin

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="TasmoAdmin"
var_tags="${var_tags:-tasmota;smarthome}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git
  msg_ok "Installed Dependencies"

  PHP_VERSION="8.4" PHP_APACHE="YES" setup_php
  fetch_and_deploy_gh_release "tasmoadmin" "TasmoAdmin/TasmoAdmin" "prebuild" "latest" "/var/www/tasmoadmin" "tasmoadmin_v*.tar.gz"

  msg_info "Configuring TasmoAdmin"
  rm -rf /etc/php/8.4/apache2/conf.d/10-opcache.ini
  chown -R www-data:www-data /var/www/tasmoadmin
  chmod 775 /var/www/tasmoadmin/tmp /var/www/tasmoadmin/data
  cat << EOF > /etc/apache2/sites-available/tasmoadmin.conf
<VirtualHost *:9999>
  ServerName tasmoadmin
  ServerAdmin webmaster@localhost
  DocumentRoot /var/www/tasmoadmin
  <Directory /var/www/tasmoadmin>
  AllowOverride All
  Order allow,deny
  allow from all
  </Directory>
  ErrorLog /var/log/apache2/error.log
  LogLevel warn
  CustomLog /var/log/apache2/access.log combined
  ServerSignature On
</VirtualHost>
EOF
  sed -i '6iListen 9999' /etc/apache2/ports.conf
  $STD a2ensite tasmoadmin
  $STD a2enmod rewrite
  systemctl reload apache2
  systemctl restart apache2
  msg_ok "Configured TasmoAdmin"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:9999${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /var ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating TasmoAdmin"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated TasmoAdmin"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
