#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Nícolas Pastorello (opastorello)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://privatebin.info/ | Github: https://github.com/PrivateBin/PrivateBin

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="PrivateBin"
var_tags="${var_tags:-paste;secure}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    nginx \
    openssl
  msg_ok "Installed Dependencies"

  PHP_VERSION="8.2" PHP_FPM="YES" setup_php
  create_self_signed_cert
  fetch_and_deploy_gh_release "privatebin" "PrivateBin/PrivateBin" "tarball"

  msg_info "Configuring Environment"
  mkdir -p /opt/privatebin/data
  cp /opt/privatebin/cfg/conf.sample.php /opt/privatebin/cfg/conf.php
  sed -i "s|// 'traffic'|'traffic'|g" /opt/privatebin/cfg/conf.php
  chown -R www-data:www-data /opt/privatebin
  chmod -R 0755 /opt/privatebin/data
  msg_ok "Configured Environment"

  msg_info "Configuring PHP"
  sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/php/8.2/fpm/php.ini
  systemctl restart php8.2-fpm
  msg_ok "Configured PHP"

  msg_info "Configuring Nginx"
  cat << EOF > /etc/nginx/sites-available/privatebin.conf
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;

    ssl_certificate /etc/ssl/privatebin/privatebin.crt;
    ssl_certificate_key /etc/ssl/privatebin/privatebin.key;

    root /opt/privatebin;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php\$is_args\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }

    add_header Strict-Transport-Security "max-age=63072000; includeSubdomains; preload";
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
}
EOF
  ln -s /etc/nginx/sites-available/privatebin.conf /etc/nginx/sites-enabled/
  rm -f /etc/nginx/sites-enabled/default
  systemctl reload nginx
  msg_ok "Nginx Configured"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}https://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/privatebin ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "privatebin" "PrivateBin/PrivateBin"; then
    msg_info "Creating backup"
    cp -f /opt/privatebin/cfg/conf.php /tmp/privatebin_conf.bak
    msg_ok "Backup created"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "privatebin" "PrivateBin/PrivateBin" "tarball"

    msg_info "Configuring ${APP}"
    mkdir -p /opt/privatebin/data
    mv /tmp/privatebin_conf.bak /opt/privatebin/cfg/conf.php
    chown -R www-data:www-data /opt/privatebin
    chmod -R 0755 /opt/privatebin/data
    systemctl reload nginx php8.2-fpm
    msg_ok "Configured ${APP}"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
