#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: bvdberg01
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/pterodactyl/panel

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Pterodactyl-Panel"
var_tags="${var_tags:-gaming}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  LOCAL_IP=$(hostname -I | awk '{print $1}')

  msg_info "Installing Dependencies"
  $STD apt install -y \
    lsb-release \
    redis \
    apache2 \
    composer \
    cron
  msg_ok "Installed Dependencies"

  setup_mariadb

  msg_info "Adding PHP Repository"
  $STD curl -sSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb
  $STD dpkg -i /tmp/debsuryorg-archive-keyring.deb
  cat << EOF > /etc/apt/sources.list.d/php.sources
Types: deb
URIs: https://packages.sury.org/php/
Suites: $(lsb_release -sc)
Components: main
Signed-By: /usr/share/keyrings/deb.sury.org-php.gpg
EOF
  $STD apt update
  msg_ok "Added PHP Repository"

  msg_info "Installing PHP"
  $STD apt remove -y php8.2*
  $STD apt install -y \
    php8.4 \
    php8.4-{gd,mysql,mbstring,bcmath,xml,curl,zip,intl,fpm} \
    libapache2-mod-php8.4
  msg_ok "Installed PHP"

  msg_info "Setting up MariaDB"
  DB_NAME=panel
  DB_USER=pterodactyl
  DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  $STD mariadb -u root -e "CREATE DATABASE $DB_NAME;"
  $STD mariadb -u root -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
  $STD mariadb -u root -e "GRANT ALL ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"
  cat << EOF > ~/pterodactyl-panel.creds
pterodactyl Panel-Credentials
pterodactyl Panel Database User: $DB_USER
pterodactyl Panel Database Password: $DB_PASS
pterodactyl Panel Database Name: $DB_NAME
EOF
  msg_ok "Set up MariaDB"

  read -p "${TAB3}Provide an email address for admin login, this should be a valid email address: " ADMIN_EMAIL
  read -p "${TAB3}Enter your First Name: " NAME_FIRST
  read -p "${TAB3}Enter your Last Name: " NAME_LAST

  msg_info "Installing pterodactyl Panel"
  RELEASE=$(curl -fsSL https://api.github.com/repos/pterodactyl/panel/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  mkdir /opt/pterodactyl-panel
  cd /opt/pterodactyl-panel || exit
  curl -fsSL "https://github.com/pterodactyl/panel/releases/download/v${RELEASE}/panel.tar.gz" -o "panel.tar.gz"
  tar -xzf "panel.tar.gz"
  cp .env.example .env
  ADMIN_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  $STD composer install --no-dev --optimize-autoloader --no-interaction
  $STD php artisan key:generate --force
  $STD php artisan p:environment:setup --no-interaction --author "$ADMIN_EMAIL" --url "http://$LOCAL_IP"
  $STD php artisan p:environment:database --no-interaction --database $DB_NAME --username $DB_USER --password "$DB_PASS"
  $STD php artisan migrate --seed --force --no-interaction
  $STD php artisan p:user:make --no-interaction --admin=1 --email "$ADMIN_EMAIL" --password "$ADMIN_PASS" --name-first "$NAME_FIRST" --name-last "$NAME_LAST" --username "admin"
  echo "* * * * * php /opt/pterodactyl-panel/artisan schedule:run >> /dev/null 2>&1" | crontab -u www-data -
  chown -R www-data:www-data /opt/pterodactyl-panel/*
  chmod -R 755 /opt/pterodactyl-panel/storage/* /opt/pterodactyl-panel/bootstrap/cache/
  ln -s /opt/pterodactyl-panel /var/www/pterodactyl
  cat << EOF >> ~/pterodactyl-panel.creds

pterodactyl Admin Username: admin
pterodactyl Admin Email: $ADMIN_EMAIL
pterodactyl Admin Password: $ADMIN_PASS
EOF
  rm -rf "/opt/pterodactyl-panel/panel.tar.gz"
  rm -rf "/tmp/debsuryorg-archive-keyring.deb"
  echo "${RELEASE}" > /opt/"${APP}"_version.txt
  msg_ok "Installed pterodactyl Panel"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/pteroq.service
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /opt/pterodactyl-panel/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now pteroq
  cat << EOF > /etc/apache2/sites-available/pterodactyl.conf
<VirtualHost *:80>
    ServerName pterodactyl
    DocumentRoot /opt/pterodactyl-panel/public

    AllowEncodedSlashes On
    
    php_value upload_max_filesize 100M
    php_value post_max_size 100M

    <Directory /opt/pterodactyl-panel/public>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog /var/log/apache2/pterodactyl_error.log
    CustomLog /var/log/apache2/pterodactyl_access.log combined
</VirtualHost>
EOF
  $STD a2ensite pterodactyl
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
  if [[ ! -d /opt/pterodactyl-panel ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  setup_mariadb
  CURRENT_PHP=$(php -v 2> /dev/null | awk '/^PHP/{print $2}' | cut -d. -f1,2)

  if [[ "$CURRENT_PHP" != "8.4" ]]; then
    msg_info "Migrating PHP $CURRENT_PHP to 8.4"
    $STD curl -fsSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb
    $STD dpkg -i /tmp/debsuryorg-archive-keyring.deb
    $STD sh -c 'echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list'
    cat << EOF > /etc/apt/sources.list.d/php.sources
Types: deb
URIs: https://packages.sury.org/php/
Suites: $(lsb_release -sc)
Components: main
Signed-By: /usr/share/keyrings/deb.sury.org-php.gpg
EOF
    $STD apt update
    $STD apt remove -y php"${CURRENT_PHP//./}"*
    $STD apt install -y \
      php8.4 \
      php8.4-{gd,mysql,mbstring,bcmath,xml,curl,zip,intl,fpm} \
      libapache2-mod-php8.4

    msg_ok "Migrated PHP $CURRENT_PHP to 8.4"
  fi

  RELEASE=$(curl -fsSL https://api.github.com/repos/pterodactyl/panel/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
    msg_info "Stopping Service"
    cd /opt/pterodactyl-panel || exit
    $STD php artisan down
    msg_ok "Stopped Service"

    msg_info "Updating ${APP} to v${RELEASE}"
    cp -r /opt/pterodactyl-panel/.env /opt/
    rm -rf * .*
    curl -fsSL "https://github.com/pterodactyl/panel/releases/download/v${RELEASE}/panel.tar.gz" -o "$(basename "https://github.com/pterodactyl/panel/releases/download/v${RELEASE}/panel.tar.gz")"
    tar -xzf "panel.tar.gz"
    mv /opt/.env /opt/pterodactyl-panel/
    $STD composer install --no-dev --optimize-autoloader --no-interaction
    $STD php artisan view:clear
    $STD php artisan config:clear
    $STD php artisan migrate --seed --force --no-interaction
    chown -R www-data:www-data /opt/pterodactyl-panel/*
    chmod -R 755 /opt/pterodactyl-panel/storage /opt/pterodactyl-panel/bootstrap/cache/
    ln -s /opt/pterodactyl-panel /var/www/pterodactyl
    rm -rf "/opt/pterodactyl-panel/panel.tar.gz"
    echo "${RELEASE}" > /opt/${APP}_version.txt
    msg_ok "Updated $APP to v${RELEASE}"

    msg_info "Starting Service"
    $STD php artisan queue:restart
    $STD php artisan up
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
