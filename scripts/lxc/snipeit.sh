#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Michel Roegl-Brunner (michelroegl-brunner)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://snipeitapp.com/ | Github: https://github.com/grokability/snipe-it

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="SnipeIT"
var_tags="${var_tags:-asset-management;foss}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    git \
    nginx
  msg_ok "Installed Dependencies"

  PHP_VERSION="8.3" PHP_FPM="YES" PHP_MODULE="ldap,soap,xsl" setup_php
  setup_composer
  fetch_and_deploy_gh_release "snipe-it" "grokability/snipe-it" "tarball"
  setup_mariadb
  MARIADB_DB_NAME="snipeit_db" MARIADB_DB_USER="snipeit" setup_mariadb_db

  msg_info "Configuring Snipe-IT"
  cd /opt/snipe-it || exit
  cp .env.example .env
  sed -i -e "s|^APP_URL=.*|APP_URL=http://${LOCAL_IP}|" \
    -e "s|^DB_DATABASE=.*|DB_DATABASE=${MARIADB_DB_NAME}|" \
    -e "s|^DB_USERNAME=.*|DB_USERNAME=${MARIADB_DB_USER}|" \
    -e "s|^DB_PASSWORD=.*|DB_PASSWORD=${MARIADB_DB_PASS}|" .env
  chown -R www-data: /opt/snipe-it
  chmod -R 755 /opt/snipe-it
  export COMPOSER_ALLOW_SUPERUSER=1
  $STD composer install --no-dev --optimize-autoloader --no-interaction
  $STD php artisan key:generate --force
  msg_ok "Configured Snipe-IT"

  msg_info "Creating Service"
  cat << EOF > /etc/nginx/conf.d/snipeit.conf
server {
        listen 80;
        root /opt/snipe-it/public;
        server_name ${LOCAL_IP};
        client_max_body_size 100M;
        index index.php;

        location / {
                try_files \$uri \$uri/ /index.php?\$query_string;
        }

        location ~ \.php\$ {
                include fastcgi.conf;
                include snippets/fastcgi-php.conf;
                fastcgi_pass unix:/run/php/php8.3-fpm.sock;
                fastcgi_split_path_info ^(.+\.php)(/.+)\$;
                fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
                include fastcgi_params;
        }
}
EOF
  systemctl reload nginx
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/snipe-it ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  setup_mariadb
  if ! grep -q "client_max_body_size[[:space:]]\+100M;" /etc/nginx/conf.d/snipeit.conf; then
    sed -i '/index index.php;/i \        client_max_body_size 100M;' /etc/nginx/conf.d/snipeit.conf
  fi

  if check_for_gh_release "snipe-it" "grokability/snipe-it"; then
    msg_info "Stopping Services"
    systemctl stop nginx
    msg_ok "Services Stopped"

    msg_info "Creating Backup"
    mv /opt/snipe-it /opt/snipe-it-backup
    msg_ok "Created Backup"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "snipe-it" "grokability/snipe-it" "tarball"
    [[ "$(php -v 2> /dev/null)" == PHP\ 8.2* ]] && PHP_VERSION="8.3" PHP_FPM="YES" PHP_MODULE="ldap,soap,xsl" setup_php
    sed -i 's/php8.2/php8.3/g' /etc/nginx/conf.d/snipeit.conf
    setup_composer

    msg_info "Updating Snipe-IT"
    $STD apt update
    $STD apt -y upgrade
    cp /opt/snipe-it-backup/.env /opt/snipe-it/.env
    cp -r /opt/snipe-it-backup/public/uploads/. /opt/snipe-it/public/uploads/
    cp -r /opt/snipe-it-backup/storage/private_uploads/. /opt/snipe-it/storage/private_uploads/
    cd /opt/snipe-it/ || exit
    export COMPOSER_ALLOW_SUPERUSER=1
    $STD composer install --no-dev --optimize-autoloader --no-interaction
    $STD composer dump-autoload
    $STD php artisan migrate --force
    $STD php artisan config:clear
    $STD php artisan route:clear
    $STD php artisan cache:clear
    $STD php artisan view:clear
    chown -R www-data: /opt/snipe-it
    chmod -R 755 /opt/snipe-it
    rm -rf /opt/snipe-it-backup
    msg_ok "Updated Snipe-IT"

    msg_info "Starting Service"
    systemctl start nginx
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
