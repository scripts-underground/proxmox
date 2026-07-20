#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Omar Minaya | MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://linkstack.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="LinkStack"
var_tags="${var_tags:-os}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  PHP_VERSION="8.3" PHP_APACHE="YES" setup_php
  fetch_and_deploy_gh_release "linkstack" "linkstackorg/linkstack" "prebuild" "latest" "/var/www/html/" "linkstack.zip"

  msg_info "Configuring LinkStack"
  $STD a2enmod rewrite
  chown -R www-data:www-data /var/www/html/linkstack
  chmod -R 755 /var/www/html/linkstack

  cat << EOF > /etc/apache2/sites-available/linkstack.conf
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html/linkstack
    ErrorLog /var/log/apache2/linkstack-error.log
    CustomLog /var/log/apache2/linkstack-access.log combined
    <Directory /var/www/html/linkstack/>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
  $STD a2dissite 000-default.conf
  $STD a2ensite linkstack.conf
  $STD systemctl restart apache2
  msg_ok "Configured LinkStack"
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

  if [[ ! -f ~/.linkstack ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  PHP_VERSION="8.3" PHP_APACHE="YES" setup_php
  msg_warn "LinkStack should be updated via the user interface."
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
