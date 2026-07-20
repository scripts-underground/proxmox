#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://koel.dev/ | Github: https://github.com/koel/koel

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Koel"
var_tags="${var_tags:-music;streaming}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    nginx \
    ffmpeg \
    cron \
    locales
  msg_ok "Installed Dependencies"

  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="koel" PG_DB_USER="koel" setup_postgresql_db
  PHP_VERSION="8.4" PHP_FPM="YES" setup_php
  NODE_VERSION="22" NODE_MODULE="pnpm" setup_nodejs
  setup_composer

  fetch_and_deploy_gh_release "koel" "koel/koel" "prebuild" "latest" "/opt/koel" "koel-*.tar.gz"

  msg_info "Configuring Koel"
  mkdir -p /opt/koel_media /opt/koel_sync
  cd /opt/koel || exit
  cat << EOF > /opt/koel/.env
APP_NAME=Koel
APP_ENV=production
APP_DEBUG=false
APP_URL=http://${LOCAL_IP}
APP_KEY=

TRUSTED_HOSTS=

DB_CONNECTION=pgsql
DB_HOST=127.0.0.1
DB_PORT=5432
DB_DATABASE=${PG_DB_NAME}
DB_USERNAME=${PG_DB_USER}
DB_PASSWORD=${PG_DB_PASS}

STORAGE_DRIVER=local
MEDIA_PATH=/opt/koel_media
ARTIFACTS_PATH=

IGNORE_DOT_FILES=true
APP_MAX_SCAN_TIME=600
MEMORY_LIMIT=

STREAMING_METHOD=php
SCOUT_DRIVER=tntsearch

USE_MUSICBRAINZ=true
MUSICBRAINZ_USER_AGENT=

LASTFM_API_KEY=
LASTFM_API_SECRET=

SPOTIFY_CLIENT_ID=
SPOTIFY_CLIENT_SECRET=

YOUTUBE_API_KEY=

CDN_URL=

TRANSCODE_FLAC=false
FFMPEG_PATH=/usr/bin/ffmpeg
TRANSCODE_BIT_RATE=128

ALLOW_DOWNLOAD=true
BACKUP_ON_DELETE=true

MEDIA_BROWSER_ENABLED=false

PROXY_AUTH_ENABLED=false

SYNC_LOG_LEVEL=error
FORCE_HTTPS=

MAIL_FROM_ADDRESS="noreply@localhost"
MAIL_FROM_NAME="Koel"
MAIL_MAILER=log
MAIL_HOST=null
MAIL_PORT=null
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=null

BROADCAST_CONNECTION=log
CACHE_DRIVER=file
FILESYSTEM_DISK=local
QUEUE_CONNECTION=sync
SESSION_DRIVER=file
SESSION_LIFETIME=120
EOF

  mkdir -p /opt/koel/storage/{app/public,framework/{cache/data,sessions,views},logs}
  chown -R www-data:www-data /opt/koel /opt/koel_media /opt/koel_sync
  chmod -R 775 /opt/koel/storage /opt/koel/bootstrap/cache
  msg_ok "Configured Koel"

  msg_info "Installing Koel (Patience)"
  export COMPOSER_ALLOW_SUPERUSER=1
  cd /opt/koel || exit
  $STD composer install --no-interaction --no-dev --optimize-autoloader
  $STD php artisan key:generate --force
  $STD php artisan config:clear
  $STD php artisan cache:clear
  $STD php artisan koel:init --no-assets --no-interaction
  chown -R www-data:www-data /opt/koel
  msg_ok "Installed Koel"

  msg_info "Tuning PHP-FPM"
  PHP_FPM_CONF="/etc/php/8.4/fpm/pool.d/www.conf"
  sed -i 's/^pm.max_children = .*/pm.max_children = 15/' "$PHP_FPM_CONF"
  sed -i 's/^pm.start_servers = .*/pm.start_servers = 4/' "$PHP_FPM_CONF"
  sed -i 's/^pm.min_spare_servers = .*/pm.min_spare_servers = 2/' "$PHP_FPM_CONF"
  sed -i 's/^pm.max_spare_servers = .*/pm.max_spare_servers = 8/' "$PHP_FPM_CONF"
  $STD systemctl restart php8.4-fpm
  msg_ok "Tuned PHP-FPM"

  msg_info "Configuring Nginx"
  cat << 'EOF' > /etc/nginx/sites-available/koel
server {
    listen 80;
    server_name _;
    root /opt/koel/public;
    index index.php;

    client_max_body_size 50M;
    charset utf-8;

    gzip on;
    gzip_types text/plain text/css application/x-javascript text/xml application/xml application/xml+rss text/javascript application/json;
    gzip_comp_level 9;

    send_timeout 3600;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location /media/ {
        internal;
        alias $upstream_http_x_media_root;
    }

    location ~ \.php$ {
        try_files $uri $uri/ /index.php?$args;
        fastcgi_pass unix:/run/php/php8.4-fpm.sock;
        fastcgi_index index.php;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_intercept_errors on;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_param PATH_TRANSLATED $document_root$fastcgi_path_info;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF
  rm -f /etc/nginx/sites-enabled/default
  ln -sf /etc/nginx/sites-available/koel /etc/nginx/sites-enabled/koel
  $STD systemctl reload nginx
  msg_ok "Configured Nginx"

  msg_info "Setting up Cron Job"
  cat << 'EOF' > /etc/cron.d/koel
0 * * * * www-data cd /opt/koel && /usr/bin/php artisan koel:scan >/dev/null 2>&1
EOF
  chmod 644 /etc/cron.d/koel
  msg_ok "Set up Cron Job"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/koel ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "koel" "koel/koel"; then
    msg_info "Stopping Services"
    systemctl stop nginx php8.4-fpm
    msg_ok "Stopped Services"

    msg_info "Creating Backup"
    mkdir -p /tmp/koel_backup
    cp /opt/koel/.env /tmp/koel_backup/
    cp -r /opt/koel/storage /tmp/koel_backup/ 2> /dev/null || true
    cp -r /opt/koel/public/img /tmp/koel_backup/ 2> /dev/null || true
    msg_ok "Created Backup"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "koel" "koel/koel" "prebuild" "latest" "/opt/koel" "koel-*.tar.gz"

    msg_info "Restoring Data"
    cp /tmp/koel_backup/.env /opt/koel/
    cp -r /tmp/koel_backup/storage/* /opt/koel/storage/ 2> /dev/null || true
    cp -r /tmp/koel_backup/img/* /opt/koel/public/img/ 2> /dev/null || true
    rm -rf /tmp/koel_backup
    msg_ok "Restored Data"

    msg_info "Running Migrations"
    cd /opt/koel || exit
    export COMPOSER_ALLOW_SUPERUSER=1
    $STD composer install --no-interaction --no-dev --optimize-autoloader
    $STD php artisan migrate --force
    $STD php artisan config:clear
    $STD php artisan cache:clear
    $STD php artisan view:clear
    $STD php artisan koel:init --no-assets --no-interaction
    chown -R www-data:www-data /opt/koel
    chmod -R 775 /opt/koel/storage
    msg_ok "Ran Migrations"

    msg_info "Starting Services"
    systemctl start php8.4-fpm nginx
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
