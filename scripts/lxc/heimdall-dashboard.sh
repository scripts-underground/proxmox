#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://heimdall.site/

APP="Heimdall-Dashboard"
var_tags="${var_tags:-dashboard}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    nginx \
    git
  msg_ok "Installed Dependencies"

  setup_composer

  msg_info "Installing Heimdall-Dashboard"
  fetch_and_deploy_gh_release "Heimdall" "linuxserver/Heimdall" "tarball"
  cd /opt/Heimdall || exit
  cp .env.example .env
  export COMPOSER_ALLOW_SUPERUSER=1
  $STD composer install --no-dev --no-interaction
  $STD php artisan key:generate
  sed -i "s/APP_NAME=Heimdall/APP_NAME=Heimdall-Dashboard/" .env
  msg_ok "Installed Heimdall-Dashboard"

  msg_info "Configuring Nginx"
  PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
  PHP_FPM_SOCK=$(find /run/php -maxdepth 1 -name "php*-fpm.sock" -type s | sort -V | tail -1)
  unlink /etc/nginx/sites-enabled/default
  rm -f /etc/nginx/sites-available/default
  cat << EOF > /etc/nginx/sites-available/heimdall
server {
    listen 7990;
    server_name _;
    root /opt/Heimdall/public;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/\$|.+\$);
        fastcgi_pass unix:${PHP_FPM_SOCK};
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/heimdall /etc/nginx/sites-enabled/heimdall
  systemctl enable -q --now php${PHP_VER}-fpm
  $STD nginx -t
  systemctl enable -q --now nginx
  $STD nginx -s reload
  msg_ok "Configured Nginx"

  msg_info "Setting Permissions"
  chown -R www-data:www-data /opt/Heimdall/
  chmod -R 755 /opt/Heimdall/
  msg_ok "Set Permissions"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:7990${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/Heimdall ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "Heimdall" "linuxserver/Heimdall"; then
    msg_info "Stopping Services"
    PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
    systemctl stop nginx "php${PHP_VER}-fpm"
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    create_backup /opt/Heimdall/database \
      /opt/Heimdall/public \
      /opt/Heimdall/.env
    msg_ok "Backed up Data"

    setup_composer
    fetch_and_deploy_gh_release "Heimdall" "linuxserver/Heimdall" "tarball"

    msg_info "Updating Heimdall-Dashboard"
    cd /opt/Heimdall || exit
    restore_backup
    export COMPOSER_ALLOW_SUPERUSER=1
    $STD composer install --no-dev --no-interaction
    $STD php artisan key:generate
    msg_ok "Updated Heimdall-Dashboard"

    msg_info "Setting Permissions"
    chown -R www-data:www-data /opt/Heimdall/
    chmod -R 755 /opt/Heimdall/
    msg_ok "Set Permissions"

    msg_info "Starting Services"
    systemctl start "php${PHP_VER}-fpm" nginx
    msg_ok "Started Services"
    msg_ok "Update Successful"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
