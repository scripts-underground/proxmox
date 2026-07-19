#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://mariadb.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-MariaDB"
var_tags="${var_tags:-alpine;database}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing MariaDB"
  $STD apk add mariadb mariadb-openrc
  $STD rc-update add mariadb default
  msg_ok "Installed MariaDB"
  msg_info "Configuring MariaDB"
  mysql_install_db --user=mysql --basedir=/usr --datadir=/var/lib/mysql > /dev/null 2>&1
  $STD rc-service mariadb start
  msg_ok "MariaDB Configured"

  read -r -p "${TAB3}Would you like to install Adminer with lighttpd? <y/N>: " prompt
  if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
    msg_info "Installing Adminer and dependencies"
    $STD apk add --no-cache \
      lighttpd lighttpd-openrc php83 php83-cgi php83-common php83-curl \
      php83-gd php83-mbstring php83-mysqli php83-mysqlnd php83-openssl \
      php83-zip php83-session jq
    sed -i 's|# *include "mod_fastcgi.conf"|include "mod_fastcgi.conf"|' /etc/lighttpd/lighttpd.conf
    sed -i 's|/usr/bin/php-cgi|/usr/bin/php-cgi83|g' /etc/lighttpd/mod_fastcgi.conf
    mkdir -p /var/www/localhost/htdocs
    ADMINER_VERSION=$(curl -fsSL https://api.github.com/repos/vrana/adminer/releases/latest | jq -r '.tag_name' | sed 's/^v//')
    curl -fsSL "https://github.com/vrana/adminer/releases/download/v${ADMINER_VERSION}/adminer-${ADMINER_VERSION}.php" -o /var/www/localhost/htdocs/adminer.php
    chown lighttpd:lighttpd /var/www/localhost/htdocs/adminer.php
    chmod 755 /var/www/localhost/htdocs/adminer.php
    msg_ok "Adminer Installed"
    msg_info "Starting Lighttpd"
    $STD rc-update add lighttpd default
    $STD rc-service lighttpd restart
    msg_ok "Lighttpd Started"
  fi
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} MariaDB is running on port 3306${CL}"
}

function update_script() {
  header_info
  msg_info "Updating $APP LXC"
  $STD apk -U upgrade
  msg_ok "Updated $APP LXC"
  msg_info "Restarting MariaDB"
  rc-service mariadb restart
  msg_ok "Restarted MariaDB"
  msg_ok "Updated successfully!"
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
