#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.postgresql.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-PostgreSQL"
var_tags="${var_tags:-alpine;database}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-1}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  ver=17
  msg_info "Installing PostgreSQL ${ver}"
  $STD apk add --no-cache postgresql${ver} postgresql${ver}-contrib postgresql${ver}-openrc sudo
  msg_ok "Installed PostgreSQL ${ver}"

  msg_info "Enabling PostgreSQL Service"
  $STD rc-update add postgresql default
  msg_ok "Enabled PostgreSQL Service"

  msg_info "Starting PostgreSQL"
  $STD rc-service postgresql start
  msg_ok "Started PostgreSQL"

  msg_info "Configuring PostgreSQL for External Access"
  conf_file="/etc/postgresql${ver}/postgresql.conf"
  hba_file="/etc/postgresql${ver}/pg_hba.conf"
  sed -i "s/^#listen_addresses =.*/listen_addresses = '*'/" "$conf_file"
  sed -i "/^host\s\+all\s\+all\s\+127.0.0.1\/32\s\+md5/ s/.*/host all all 0.0.0.0\/0 md5/" "$hba_file"
  $STD rc-service postgresql restart
  msg_ok "Configured and Restarted PostgreSQL"

  read -r -p "${TAB3}Would you like to install Adminer with lighttpd? <y/N>: " prompt
  if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
    msg_info "Installing Adminer and dependencies"
    $STD apk add --no-cache \
      lighttpd lighttpd-openrc php83 php83-cgi php83-common php83-curl php83-gd \
      php83-mbstring php83-pdo php83-pgsql php83-openssl php83-zip php83-session jq
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
  echo -e "${INFO}${YW} PostgreSQL is running on port 5432${CL}"
}

function update_script() {
  header_info
  msg_info "Updating Alpine Packages"
  $STD apk -U upgrade
  msg_ok "Updated Alpine Packages"
  msg_info "Updating PostgreSQL"
  $STD apk upgrade postgresql postgresql-contrib
  msg_ok "Updated PostgreSQL"
  msg_ok "Updated successfully!"
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
