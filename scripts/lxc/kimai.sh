#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.kimai.org/ | Github: https://github.com/kimai/kimai

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Kimai"
var_tags="${var_tags:-time-tracking}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-7}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    apt-transport-https \
    apache2 \
    git \
    expect
  msg_ok "Installed Dependencies"

  setup_mariadb
  PHP_VERSION="8.4" PHP_APACHE="YES" setup_php
  setup_composer

  msg_info "Setting up database"
  DB_NAME=kimai_db
  DB_USER=kimai
  DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  MYSQL_VERSION=$(mariadb --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
  $STD mariadb -e "CREATE DATABASE $DB_NAME;"
  $STD mariadb -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
  $STD mariadb -e "GRANT ALL ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"
  cat << EOF > ~/kimai.creds
Kimai-Credentials
Kimai Database User: $DB_USER
Kimai Database Password: $DB_PASS
Kimai Database Name: $DB_NAME
EOF
  msg_ok "Set up database"

  fetch_and_deploy_gh_release "kimai" "kimai/kimai" "tarball"

  msg_info "Setup Kimai"
  APP_SECRET=$(openssl rand -hex 48)
  cd /opt/kimai || exit
  export COMPOSER_ALLOW_SUPERUSER=1
  $STD composer install --no-dev --optimize-autoloader --no-interaction
  cp .env.dist .env
  sed -i "/^DATABASE_URL=.*/c\DATABASE_URL=mysql://$DB_USER:$DB_PASS@127.0.0.1:3306/$DB_NAME?charset=utf8mb4&serverVersion=mariadb-$MYSQL_VERSION" /opt/kimai/.env
  sed -i "s|^APP_SECRET=.*|APP_SECRET=$APP_SECRET|" /opt/kimai/.env
  $STD bin/console kimai:install -n
  $STD expect << EOF
set timeout -1
log_user 0

spawn bin/console kimai:user:create admin admin@community-scripts.org ROLE_SUPER_ADMIN

expect "Please enter the password:"
send "community-scripts.org\r"

expect eof
EOF
  $STD composer update --no-interaction
  cat << EOF > /opt/kimai/config/packages/local.yaml
kimai:
    timesheet:
        rounding:
            default:
                begin: 15
                end: 15

EOF
  msg_ok "Installed Kimai"

  msg_info "Creating Service"
  cat << EOF > /etc/apache2/sites-available/kimai.conf
<VirtualHost *:80>
  ServerAdmin webmaster@localhost
  DocumentRoot /opt/kimai/public/

   <Directory /opt/kimai/public>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog /var/log/apache2/error.log
    CustomLog /var/log/apache2/access.log combined

</VirtualHost>
EOF
  $STD a2ensite kimai.conf
  $STD a2dissite 000-default.conf
  $STD systemctl reload apache2
  msg_ok "Created Service"

  msg_info "Setup Permissions"
  chown -R :www-data /opt/*
  chmod -R g+r /opt/*
  chmod -R g+rw /opt/*
  chown -R www-data:www-data /opt/*
  chmod -R 777 /opt/*
  msg_ok "Setup Permissions"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  ensure_dependencies lsb-release
  if [[ ! -d /opt/kimai ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  setup_mariadb

  PHP_VERSION="8.4" PHP_APACHE="YES" setup_php
  setup_composer

  if check_for_gh_release "kimai" "kimai/kimai"; then
    msg_info "Stopping Apache2"
    systemctl stop apache2
    msg_ok "Stopped Apache2"

    create_backup /opt/kimai/var \
      /opt/kimai/.env \
      /opt/kimai/config/packages/local.yaml
    fetch_and_deploy_gh_release "kimai" "kimai/kimai" "tarball"
    restore_backup

    msg_info "Updating Kimai"
    if grep -q "^APP_SECRET=$" /opt/kimai/.env; then
      APP_SECRET=$(openssl rand -hex 48)
      sed -i "s|^APP_SECRET=.*|APP_SECRET=${APP_SECRET}|" /opt/kimai/.env
    fi

    cd /opt/kimai || exit
    sed -i '/^admin_lte:/,/^[^[:space:]]/d' config/packages/local.yaml
    $STD composer install --no-dev --optimize-autoloader
    $STD bin/console kimai:update
    msg_ok "Updated Kimai"

    msg_info "Starting Apache2"
    systemctl start apache2
    msg_ok "Started Apache2"

    msg_info "Setup Permissions"
    chown -R :www-data /opt/*
    chmod -R g+r /opt/*
    chmod -R g+rw /opt/*
    chown -R www-data:www-data /opt/*
    chmod -R 777 /opt/*
    msg_ok "Setup Permissions"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
