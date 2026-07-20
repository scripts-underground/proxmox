#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: bvdberg01
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://koillection.github.io/ | Github: https://github.com/benjaminjonard/koillection

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Koillection"
var_tags="${var_tags:-network}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  NODE_VERSION="26" NODE_MODULE="yarn" setup_nodejs
  PG_VERSION="16" setup_postgresql
  PHP_VERSION="8.5" PHP_APACHE="YES" setup_php
  setup_composer
  PG_DB_NAME="koillection" PG_DB_USER="koillection" setup_postgresql_db

  fetch_and_deploy_gh_release "koillection" "benjaminjonard/koillection" "tarball"

  msg_info "Configuring Koillection"
  cd /opt/koillection || exit
  cp /opt/koillection/.env /opt/koillection/.env.local
  APP_SECRET=$(openssl rand -base64 32)
  sed -i \
    -e "s|^APP_ENV=.*|APP_ENV=prod|" \
    -e "s|^APP_DEBUG=.*|APP_DEBUG=0|" \
    -e "s|^APP_SECRET=.*|APP_SECRET=${APP_SECRET}|" \
    -e "s|^DB_NAME=.*|DB_NAME=${PG_DB_NAME}|" \
    -e "s|^DB_USER=.*|DB_USER=${PG_DB_USER}|" \
    -e "s|^DB_PASSWORD=.*|DB_PASSWORD=${PG_DB_PASS}|" \
    /opt/koillection/.env.local
  echo 'APP_RUNTIME="Symfony\Component\Runtime\SymfonyRuntime"' >> /opt/koillection/.env.local
  export COMPOSER_ALLOW_SUPERUSER=1
  export APP_RUNTIME='Symfony\Component\Runtime\SymfonyRuntime'
  $STD composer install --no-dev -o --no-interaction --classmap-authoritative
  $STD php bin/console doctrine:migrations:migrate --no-interaction
  $STD php bin/console app:translations:dump
  cd assets/ || exit
  $STD yarn install
  $STD yarn build
  mkdir -p /opt/koillection/public/uploads
  chown -R www-data:www-data /opt/koillection/public/uploads
  msg_ok "Configured Koillection"

  msg_info "Creating Service"
  cat << EOF > /etc/apache2/sites-available/koillection.conf
<VirtualHost *:80>
    ServerName koillection
    DocumentRoot /opt/koillection/public
    SetEnv APP_RUNTIME "Symfony\\Component\\Runtime\\SymfonyRuntime"
    <Directory /opt/koillection/public>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
        RewriteEngine On
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d
        RewriteRule ^(.*)$ index.php/\$1 [L]
    </Directory>

    ErrorLog /var/log/apache2/koillection_error.log
    CustomLog /var/log/apache2/koillection_access.log combined
</VirtualHost>
EOF
  $STD a2ensite koillection
  $STD a2enmod rewrite
  $STD a2dissite 000-default.conf
  $STD systemctl reload apache2
  msg_ok "Created Service"
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
  if [[ ! -d /opt/koillection ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "koillection" "benjaminjonard/koillection"; then
    msg_info "Stopping Service"
    systemctl stop apache2
    msg_ok "Stopped Service"

    PHP_VERSION="8.5" PHP_APACHE="YES" setup_php
    setup_composer

    msg_info "Creating a backup"
    mv /opt/koillection/ /opt/koillection-backup
    msg_ok "Backup created"

    fetch_and_deploy_gh_release "koillection" "benjaminjonard/koillection" "tarball"

    msg_info "Updating Koillection"
    cp -r /opt/koillection-backup/.env.local /opt/koillection
    cp -r /opt/koillection-backup/public/uploads/. /opt/koillection/public/uploads/

    # Ensure APP_RUNTIME is in .env.local for CLI commands (upgrades from older versions)
    if ! grep -q "APP_RUNTIME" /opt/koillection/.env.local 2> /dev/null; then
      [[ -s /opt/koillection/.env.local && -n "$(tail -c 1 /opt/koillection/.env.local)" ]] && echo "" >> /opt/koillection/.env.local
      echo 'APP_RUNTIME="Symfony\Component\Runtime\SymfonyRuntime"' >> /opt/koillection/.env.local
    fi
    NODE_VERSION="26" NODE_MODULE="yarn" setup_nodejs
    cd /opt/koillection || exit
    export COMPOSER_ALLOW_SUPERUSER=1
    export APP_RUNTIME='Symfony\Component\Runtime\SymfonyRuntime'
    $STD composer install --no-dev -o --no-interaction --classmap-authoritative
    $STD php bin/console doctrine:migrations:migrate --no-interaction
    $STD php bin/console app:translations:dump
    cd assets/ || exit
    $STD yarn install
    $STD yarn build
    mkdir -p /opt/koillection/public/uploads
    mkdir -p /opt/koillection/var/log
    chown -R www-data:www-data /opt/koillection/var/log
    chown -R www-data:www-data /opt/koillection/public/uploads
    rm -r /opt/koillection-backup

    # Ensure APP_RUNTIME is set in Apache config (for upgrades from older versions)
    if ! grep -q "APP_RUNTIME" /etc/apache2/sites-available/koillection.conf 2> /dev/null; then
      sed -i '/<VirtualHost/a\    SetEnv APP_RUNTIME "Symfony\\Component\\Runtime\\SymfonyRuntime"' /etc/apache2/sites-available/koillection.conf
    fi
    msg_ok "Updated Koillection"

    msg_info "Starting Service"
    systemctl start apache2
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
