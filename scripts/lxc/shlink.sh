#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://shlink.io/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Shlink"
var_tags="${var_tags:-url-shortener;analytics;php}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  PHP_VERSION="8.5" setup_php
  setup_mariadb
  MARIADB_DB_NAME="shlink" MARIADB_DB_USER="shlink" setup_mariadb_db

  fetch_and_deploy_gh_release "shlink" "shlinkio/shlink" "prebuild" "latest" "/opt/shlink" "shlink*_php8.5_dist.zip"

  msg_info "Setting up Application"
  cd /opt/shlink || exit
  $STD php ./vendor/bin/rr get --no-interaction --location bin/
  chmod +x bin/rr
  mkdir -p data/cache data/locks data/log data/proxies data/temp-geolite
  chmod -R 775 data
  cat << EOF > /opt/shlink/.env
DEFAULT_DOMAIN=${LOCAL_IP}:8080
IS_HTTPS_ENABLED=false
DB_DRIVER=maria
DB_NAME=${MARIADB_DB_NAME}
DB_USER=${MARIADB_DB_USER}
DB_PASSWORD=${MARIADB_DB_PASS}
DB_HOST=127.0.0.1
DB_PORT=3306
EOF
  set -a
  source /opt/shlink/.env
  set +a
  $STD php vendor/bin/shlink-installer init --no-interaction --clear-db-cache --skip-download-geolite
  API_OUTPUT=$(php bin/cli api-key:generate --name=default 2>&1)
  INITIAL_API_KEY=$(echo "$API_OUTPUT" | sed -n 's/.*Generated API key: "\([^"]*\)".*/\1/p')
  if [[ -n "$INITIAL_API_KEY" ]]; then
    echo "INITIAL_API_KEY=${INITIAL_API_KEY}" >> /opt/shlink/.env
  fi
  msg_ok "Set up Application"

  msg_info "Installing Web Client Dependencies"
  $STD apt install -y nginx
  msg_ok "Installed Web Client Dependencies"

  fetch_and_deploy_gh_release "shlink-web-client" "shlinkio/shlink-web-client" "prebuild" "latest" "/opt/shlink-web-client" "shlink-web-client_*_dist.zip"

  msg_info "Setting up Web Client"
  cat << EOF > /opt/shlink-web-client/servers.json
[
  {
    "name": "Shlink",
    "url": "http://${LOCAL_IP}:8080",
    "apiKey": "${INITIAL_API_KEY}"
  }
]
EOF
  cat << 'EOF' > /etc/nginx/sites-available/shlink-web-client
server {
    listen 3000 default_server;
    charset utf-8;
    root /opt/shlink-web-client;
    index index.html;

    location ~* \.(?:manifest|appcache|html?|xml|json)$ {
        expires -1;
    }

    location ~* \.(?:jpg|jpeg|gif|png|ico|cur|gz|svg|svgz|mp4|ogg|ogv|webm|htc)$ {
        expires 1M;
        add_header Cache-Control "public";
    }

    location ~* \.(?:css|js)$ {
        expires 1y;
        add_header Cache-Control "public";
    }

    location = /servers.json {
        try_files /servers.json /conf.d/servers.json;
    }

    location / {
        try_files $uri $uri/ /index.html$is_args$args;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/shlink-web-client /etc/nginx/sites-enabled/shlink-web-client
  rm -f /etc/nginx/sites-enabled/default
  systemctl enable -q nginx
  $STD systemctl restart nginx
  msg_ok "Set up Web Client"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/shlink.service
[Unit]
Description=Shlink URL Shortener
After=network.target mariadb.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/shlink
EnvironmentFile=/opt/shlink/.env
ExecStart=/opt/shlink/bin/rr serve -c config/roadrunner/.rr.yml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now shlink
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access Shlink Web Client using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
  echo -e "${INFO}${YW}Shlink HTTP API:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
  echo -e "${INFO}${YW}Initial API Key is stored in /opt/shlink/.env${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/shlink ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "shlink" "shlinkio/shlink"; then
    msg_info "Stopping Service"
    systemctl stop shlink
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration"
    cp /opt/shlink/.env /opt/shlink/.env.bak
    cp -r /opt/shlink/data /opt/shlink/data.bak
    msg_ok "Backed up Configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "shlink" "shlinkio/shlink" "prebuild" "latest" "/opt/shlink" "shlink*_php8.5_dist.zip"

    msg_info "Restoring Configuration"
    mv /opt/shlink/.env.bak /opt/shlink/.env
    rm -rf /opt/shlink/data
    mv /opt/shlink/data.bak /opt/shlink/data
    msg_ok "Restored Configuration"

    msg_info "Updating Application"
    cd /opt/shlink || exit
    $STD php ./vendor/bin/rr get --no-interaction --location bin/
    chmod +x bin/rr
    set -a
    source /opt/shlink/.env
    set +a
    $STD php vendor/bin/shlink-installer init --no-interaction --clear-db-cache --skip-download-geolite
    msg_ok "Updated Application"

    msg_info "Starting Service"
    systemctl start shlink
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi

  if [[ -d /opt/shlink-web-client ]]; then
    if check_for_gh_release "shlink-web-client" "shlinkio/shlink-web-client"; then
      CLEAN_INSTALL=1 fetch_and_deploy_gh_release "shlink-web-client" "shlinkio/shlink-web-client" "prebuild" "latest" "/opt/shlink-web-client" "shlink-web-client_*_dist.zip"
      msg_ok "Updated Web Client"
    fi
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
