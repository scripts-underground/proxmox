#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Nícolas Pastorello (opastorello)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.paymenter.org | Github: https://github.com/paymenter/paymenter

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Paymenter"
var_tags="${var_tags:-hosting;ecommerce;marketplace}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    git \
    nginx \
    redis-server \
    cron
  msg_ok "Installed Dependencies"

  setup_mariadb
  PHP_VERSION="8.3" PHP_FPM="YES" setup_php
  setup_composer

  fetch_and_deploy_gh_release "paymenter" "paymenter/paymenter" "prebuild" "latest" "/opt/paymenter" "paymenter.tar.gz"
  chmod -R 755 /opt/paymenter/storage/* /opt/paymenter/bootstrap/cache/

  msg_info "Setting up Database"
  DB_NAME=paymenter
  DB_USER=paymenter
  DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  mariadb-tzinfo-to-sql /usr/share/zoneinfo | mariadb mysql
  $STD mariadb -u root -e "CREATE DATABASE $DB_NAME;"
  $STD mariadb -u root -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
  $STD mariadb -u root -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost' WITH GRANT OPTION;"
  cat << EOF > /root/paymenter_db.creds
Paymenter Database Credentials
Database: $DB_NAME
Username: $DB_USER
Password: $DB_PASS
EOF

  cd /opt/paymenter || exit
  cp .env.example .env
  $STD composer install --no-dev --optimize-autoloader --no-interaction
  $STD php artisan key:generate --force
  $STD php artisan storage:link
  sed -i "s/^DB_DATABASE=.*/DB_DATABASE=${DB_NAME}/" .env
  sed -i "s/^DB_USERNAME=.*/DB_USERNAME=${DB_USER}/" .env
  sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=${DB_PASS}/" .env
  $STD php artisan migrate --force --seed
  msg_ok "Set up Database"

  msg_info "Creating Admin User"
  $STD php artisan app:user:create paymenter admin admin@paymenter.org paymenter 1 -q
  msg_ok "Created Admin User"

  msg_info "Configuring Nginx"
  cat << 'EOF' > /etc/nginx/sites-available/paymenter.conf
server {
    listen 80;
    listen [::]:80;
    server_name localhost;
    root /opt/paymenter/public;

    index index.php;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
  ln -s /etc/nginx/sites-available/paymenter.conf /etc/nginx/sites-enabled/
  rm -f /etc/nginx/sites-enabled/default
  $STD systemctl reload nginx
  chown -R www-data:www-data /opt/paymenter/*
  msg_ok "Configured Nginx"

  msg_info "Setting up Cronjob"
  echo "* * * * * php /opt/paymenter/artisan schedule:run >> /dev/null 2>&1" | crontab -
  msg_ok "Setup Cronjob"

  msg_info "Setting up Service"
  cat << EOF > /etc/systemd/system/paymenter.service
[Unit]
Description=Paymenter Queue Worker

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /opt/paymenter/artisan queue:work
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now paymenter
  systemctl enable -q --now redis-server
  msg_ok "Setup Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:80${CL}"
  echo -e "${INFO}${YW} Admin user credentials:${CL}"
  echo -e "${TAB}${YW} Email:    ${GN}admin@paymenter.org${CL}"
  echo -e "${TAB}${YW} Password: ${GN}paymenter${CL}"
  echo -e "${INFO}${YW} Database credentials saved to /root/paymenter_db.creds${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/paymenter ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  setup_mariadb

  CURRENT_PHP=$(php -v 2> /dev/null | awk '/^PHP/{print $2}' | cut -d. -f1,2)
  if [[ "$CURRENT_PHP" != "8.3" ]]; then
    PHP_VERSION="8.3" PHP_FPM="YES" setup_php
    setup_composer
    sed -i 's|php8\.2-fpm\.sock|php8.3-fpm.sock|g' /etc/nginx/sites-available/paymenter.conf
    $STD systemctl reload nginx
  fi

  if check_for_gh_release "paymenter" "paymenter/paymenter"; then
    msg_info "Updating ${APP}"
    cd /opt/paymenter || exit
    $STD php artisan app:upgrade --no-interaction
    echo "${CHECK_UPDATE_RELEASE}" > ~/.paymenter
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
