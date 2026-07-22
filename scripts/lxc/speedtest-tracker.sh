#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: AlphaLawless
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/alexjustesen/speedtest-tracker

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Speedtest-Tracker"
var_tags="${var_tags:-monitoring}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_hostname="${var_hostname:-speedtest}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    nginx \
    sqlite3
  setcap cap_net_raw+ep /bin/ping
  msg_ok "Installed Dependencies"

  PHP_VERSION="8.4" PHP_FPM="YES" setup_php
  setup_composer
  NODE_VERSION="22" setup_nodejs
  fetch_and_deploy_gh_release "speedtest-tracker" "alexjustesen/speedtest-tracker" "tarball"

  msg_info "Installing Speedtest CLI"
  setup_deb822_repo \
    "speedtest-cli" \
    "https://packagecloud.io/ookla/speedtest-cli/gpgkey" \
    "https://packagecloud.io/ookla/speedtest-cli/debian" \
    "$(get_os_info codename)" \
    "main"
  $STD apt install -y speedtest
  msg_ok "Installed Speedtest CLI"

  msg_info "Configuring PHP-FPM runtime directory"
  mkdir -p /etc/systemd/system/php8.4-fpm.service.d/
  cat << EOF > /etc/systemd/system/php8.4-fpm.service.d/override.conf
[Service]
RuntimeDirectory=php
RuntimeDirectoryMode=0755
EOF
  msg_ok "Configured PHP-FPM runtime directory"

  msg_info "Setting up Speedtest Tracker"
  cd /opt/speedtest-tracker || exit
  APP_KEY=$(php -r "echo bin2hex(random_bytes(16));")
  TIMEZONE=$(timedatectl | grep "Time zone" | awk '{print $3}')
  cat << EOF > /opt/speedtest-tracker/.env
APP_NAME="Speedtest Tracker"
APP_ENV=production
APP_TIMEZONE=${TIMEZONE}
APP_KEY=base64:$(echo -n "$APP_KEY" | base64)
APP_DEBUG=false
APP_URL=http://${LOCAL_IP}

LOG_CHANNEL=stack
LOG_LEVEL=debug

DB_CONNECTION=sqlite
DB_DATABASE=/opt/speedtest-tracker/database/database.sqlite

BROADCAST_DRIVER=log
CACHE_DRIVER=file
FILESYSTEM_DISK=local
QUEUE_CONNECTION=sync
SESSION_DRIVER=file
SESSION_LIFETIME=120

SPEEDTEST_SCHEDULE="0 */6 * * *"
SPEEDTEST_SERVERS=
SPEEDTEST_EXTERNAL_IP_URL=https://ip.me
SPEEDTEST_INTERNET_CHECK_HOSTNAME=1.1.1.1
PRUNE_RESULTS_OLDER_THAN=0

DISPLAY_TIMEZONE=${TIMEZONE}
EOF
  mkdir -p /opt/speedtest-tracker/database
  touch /opt/speedtest-tracker/database/database.sqlite
  export COMPOSER_ALLOW_SUPERUSER=1
  $STD composer install --optimize-autoloader --no-dev
  $STD npm ci
  $STD npm run build
  $STD php artisan key:generate --force
  $STD php artisan migrate --force --seed
  $STD php artisan config:clear
  $STD php artisan cache:clear
  $STD php artisan view:clear
  chown -R www-data:www-data /opt/speedtest-tracker
  chmod -R 755 /opt/speedtest-tracker/storage
  chmod -R 755 /opt/speedtest-tracker/bootstrap/cache
  msg_ok "Set up Speedtest Tracker"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/speedtest-tracker.service
[Unit]
Description=Speedtest Tracker Queue Worker
After=network.target

[Service]
Type=simple
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /opt/speedtest-tracker/artisan queue:work --sleep=3 --tries=3 --max-time=3600
WorkingDirectory=/opt/speedtest-tracker

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now speedtest-tracker
  msg_ok "Created Service"

  msg_info "Setting up Scheduler"
  cat << EOF > /etc/cron.d/speedtest-tracker
* * * * * www-data cd /opt/speedtest-tracker && php artisan schedule:run >> /dev/null 2>&1
EOF
  msg_ok "Set up Scheduler"

  msg_info "Configuring Nginx"
  cat << EOF > /etc/nginx/sites-available/speedtest-tracker
server {
    listen 80;
    server_name _;
    root /opt/speedtest-tracker/public;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    index index.php;

    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php8.4-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF

  ln -sf /etc/nginx/sites-available/speedtest-tracker /etc/nginx/sites-enabled/
  rm -f /etc/nginx/sites-enabled/default
  systemctl reload nginx
  msg_ok "Configured Nginx"
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

  if [[ ! -d /opt/speedtest-tracker ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "speedtest-tracker" "alexjustesen/speedtest-tracker"; then
    PHP_VERSION="8.4" PHP_FPM="YES" setup_php
    setup_composer
    NODE_VERSION="22" setup_nodejs
    setcap cap_net_raw+ep /bin/ping

    msg_info "Stopping Service"
    systemctl stop speedtest-tracker
    msg_ok "Stopped Service"

    msg_info "Updating Speedtest CLI"
    $STD apt update
    $STD apt --only-upgrade install -y speedtest
    msg_ok "Updated Speedtest CLI"

    msg_info "Creating Backup"
    cp -r /opt/speedtest-tracker /opt/speedtest-tracker-backup
    msg_ok "Backup Created"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "speedtest-tracker" "alexjustesen/speedtest-tracker" "tarball"

    msg_info "Updating Speedtest Tracker"
    cp -r /opt/speedtest-tracker-backup/.env /opt/speedtest-tracker/.env
    cd /opt/speedtest-tracker || exit
    export COMPOSER_ALLOW_SUPERUSER=1
    $STD composer install --optimize-autoloader --no-dev
    $STD npm ci
    $STD npm run build
    $STD php artisan migrate --force
    $STD php artisan config:clear
    $STD php artisan cache:clear
    $STD php artisan view:clear
    chown -R www-data:www-data /opt/speedtest-tracker
    chmod -R 755 /opt/speedtest-tracker/storage
    chmod -R 755 /opt/speedtest-tracker/bootstrap/cache
    msg_ok "Updated Speedtest Tracker"

    msg_info "Starting Service"
    systemctl start speedtest-tracker
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
