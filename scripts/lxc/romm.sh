#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ) | DevelopmentCats | AlphaLawless
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://romm.app | Github: https://github.com/rommapp/romm

APP="RomM"
var_tags="${var_tags:-emulation}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-32}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_romm_minimum_free_bytes="${var_lxc_romm_minimum_free_bytes:-8589934592}"

function install_script() {
  check_available_storage_bytes "$var_lxc_romm_minimum_free_bytes" \
    /opt/romm /var/lib /var/cache "${HOME:-/root}" "${TMPDIR:-/tmp}" || return 252
  msg_info "Installing Dependencies"
  $STD apt install -y \
    acl \
    git \
    build-essential \
    libssl-dev \
    libffi-dev \
    libmagic-dev \
    python3-dev \
    python3-pip \
    python3-venv \
    libmariadb3 \
    libmariadb-dev \
    libpq-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    zlib1g-dev \
    liblzma-dev \
    libncurses5-dev \
    libncursesw5-dev \
    redis-server \
    redis-tools \
    p7zip-full \
    tzdata
  msg_ok "Installed Dependencies"

  msg_info "Installing Angie with mod_zip module"
  setup_deb822_repo \
    "angie" \
    "https://angie.software/keys/angie-signing.gpg" \
    "https://download.angie.software/angie/debian/$(get_os_info version_id)" \
    "$(get_os_info codename)" \
    "main"
  $STD apt install -y angie angie-module-zip
  sed -i '1i load_module modules/ngx_http_zip_module.so;' /etc/angie/angie.conf
  msg_ok "Installed Angie with mod_zip module"
  NODE_VERSION="24" setup_nodejs
  setup_mariadb
  MARIADB_DB_NAME="romm" MARIADB_DB_USER="romm" setup_mariadb_db

  msg_info "Creating directories"
  mkdir -p /opt/romm \
    /var/lib/romm/config \
    /var/lib/romm/resources \
    /var/lib/romm/assets/{saves,states,screenshots} \
    /var/lib/romm/library/roms \
    /var/lib/romm/library/bios
  msg_ok "Created directories"

  msg_info "Creating configuration file"
  cat << 'EOF' > /var/lib/romm/config/config.yml
# RomM Configuration File
# Documentation: https://docs.romm.app/latest/Getting-Started/Configuration-File/
# Only uncomment the lines you want to use/modify

# exclude:
#   platforms:
#     - excluded_folder_a
#   roms:
#     single_file:
#       extensions:
#         - xml
#         - txt
#       names:
#         - '._*'
#         - '*.nfo'
#     multi_file:
#       names:
#         - downloaded_media
#         - media

# system:
#   platforms:
#     gc: ngc
#     ps1: psx

# The folder name where your roms are located (relative to library path)
# filesystem:
#   roms_folder: 'roms'

# scan:
#   priority:
#     metadata:
#       - "igdb"
#       - "moby"
#       - "ss"
#       - "ra"
#     artwork:
#       - "igdb"
#       - "moby"
#       - "ss"
#     region:
#       - "us"
#       - "eu"
#       - "jp"
#     language:
#       - "en"
#   media:
#     - box2d
#     - box3d
#     - screenshot
#     - manual

# emulatorjs:
#   debug: false
#   cache_limit: null
EOF
  chmod 644 /var/lib/romm/config/config.yml
  msg_ok "Created configuration file"

  if [[ "$(dpkg --print-architecture)" != "arm64" ]]; then
    fetch_and_deploy_gh_release "RAHasher" "RetroAchievements/RALibretro" "prebuild" "latest" "/opt/RALibretro" "RAHasher-x64-Linux-*.zip"
    cp /opt/RALibretro/RAHasher /usr/bin/RAHasher
    chmod +x /usr/bin/RAHasher
  else
    msg_warn "RAHasher (RetroAchievements hashing) has no arm64 build; skipping. RA hash features will be unavailable."
  fi

  fetch_and_deploy_gh_release "romm" "rommapp/romm" "tarball"
  PYTHON_VERSION="3.13" UV_PROJECT_DIR="/opt/romm" setup_uv

  msg_info "Creating environment file"
  sed -i 's/^supervised no/supervised systemd/' /etc/redis/redis.conf
  systemctl restart redis-server
  systemctl enable -q --now redis-server
  AUTH_SECRET_KEY=$(openssl rand -hex 32)

  cat << EOF > /opt/romm/.env
ROMM_BASE_PATH=/var/lib/romm
ROMM_CONFIG_PATH=/var/lib/romm/config/config.yml
WEB_CONCURRENCY=4

DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=$MARIADB_DB_NAME
DB_USER=$MARIADB_DB_USER
DB_PASSWD=$MARIADB_DB_PASS

REDIS_HOST=127.0.0.1
REDIS_PORT=6379

ROMM_AUTH_SECRET_KEY=$AUTH_SECRET_KEY
DISABLE_DOWNLOAD_ENDPOINT_AUTH=false
DISABLE_CSRF_PROTECTION=false

SCREENSCRAPER_DEV_ID=
SCREENSCRAPER_DEV_PASSWORD=

ENABLE_RESCAN_ON_FILESYSTEM_CHANGE=true
RESCAN_ON_FILESYSTEM_CHANGE_DELAY=5

ENABLE_SCHEDULED_RESCAN=true
SCHEDULED_RESCAN_CRON=0 3 * * *
ENABLE_SCHEDULED_UPDATE_SWITCH_TITLEDB=true
SCHEDULED_UPDATE_SWITCH_TITLEDB_CRON=0 4 * * *

LOGLEVEL=INFO
EOF

  chmod 600 /opt/romm/.env
  msg_ok "Created environment file"

  msg_info "Setting up RomM Backend"
  cd /opt/romm || exit
  export UV_CONCURRENT_DOWNLOADS=1
  $STD uv sync --all-extras
  cd /opt/romm/backend || exit
  $STD uv run alembic upgrade head
  msg_ok "Set up RomM Backend"

  if [[ -f /opt/romm/backend/utils/rom_patcher/package.json ]]; then
    msg_info "Building ROM Patcher helper"
    cd /opt/romm/backend/utils/rom_patcher || exit
    $STD npm install --ignore-scripts --no-audit --no-fund
    if [[ -d node_modules/rom-patcher/rom-patcher-js ]]; then
      rm -rf rom-patcher-js
      cp -r node_modules/rom-patcher/rom-patcher-js ./rom-patcher-js
    fi
    rm -rf node_modules
    msg_ok "Built ROM Patcher helper"
  fi

  msg_info "Setting up RomM Frontend"
  cd /opt/romm/frontend || exit
  $STD npm install
  $STD npm run build

  cp -rf /opt/romm/frontend/assets/* /opt/romm/frontend/dist/assets/

  mkdir -p /opt/romm/frontend/dist/assets/romm
  ROMM_BASE=$(grep '^ROMM_BASE_PATH=' /opt/romm/.env | cut -d'=' -f2)
  ROMM_BASE=${ROMM_BASE:-/var/lib/romm}
  ln -sfn "$ROMM_BASE"/resources /opt/romm/frontend/dist/assets/romm/resources
  ln -sfn "$ROMM_BASE"/assets /opt/romm/frontend/dist/assets/romm/assets
  msg_ok "Set up RomM Frontend"

  # Vite clears dist during builds; deploy player payloads only afterwards.
  fetch_and_deploy_gh_release "ruffle" "ruffle-rs/ruffle" "prebuild" "latest" "/opt/romm/frontend/dist/assets/ruffle" "ruffle-*-web-selfhosted.zip"
  fetch_and_deploy_gh_release "EmulatorJS" "EmulatorJS/EmulatorJS" "prebuild" "v4.2.3" "/opt/romm/frontend/dist/assets/emulatorjs" "4.2.3.7z"
  if [[ ! -s /opt/romm/frontend/dist/assets/emulatorjs/data/loader.js || ! -s /opt/romm/frontend/dist/assets/ruffle/ruffle.js ]]; then
    msg_error "Player payloads are missing from the built frontend"
    exit 1
  fi

  msg_info "Configuring Angie"
  cat << 'EOF' > /etc/angie/http.d/romm.conf
upstream romm_backend {
    server 127.0.0.1:5000;
}

map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}

server {
    listen 80;
    server_name _;
    root /opt/romm/frontend/dist;
    client_max_body_size 0;

    # Frontend SPA
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Static assets
    location /assets {
        alias /opt/romm/frontend/dist/assets;
        try_files $uri $uri/ =404;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # EmulatorJS player - requires COOP/COEP headers for SharedArrayBuffer
    # (serve the SPA shell directly: an internal redirect via try_files would
    # drop this location's add_headers, breaking threaded wasm cores)
    location ~ ^/rom/.*/ejs$ {
        add_header Cross-Origin-Embedder-Policy "require-corp" always;
        add_header Cross-Origin-Opener-Policy "same-origin" always;
        default_type text/html;
        alias /opt/romm/frontend/dist/index.html;
    }

    # Backend API
    location /api {
        proxy_pass http://romm_backend;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # WebSocket and Netplay
    location ~ ^/(ws|netplay) {
        proxy_pass http://romm_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }

    # OpenAPI docs
    location = /openapi.json {
        proxy_pass http://romm_backend;
    }

    # Internal library file serving
    location /library/ {
        internal;
        alias /var/lib/romm/library/;
    }
}
EOF

  sed -i "s|alias /var/lib/romm/library/;|alias ${ROMM_BASE}/library/;|" /etc/angie/http.d/romm.conf
  rm -f /etc/angie/http.d/default.conf
  systemctl restart angie
  systemctl enable -q --now angie
  msg_ok "Configured Angie"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/romm-backend.service
[Unit]
Description=RomM Backend
After=network.target mariadb.service redis-server.service
Requires=mariadb.service redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/romm/backend
EnvironmentFile=/opt/romm/.env
Environment="PYTHONPATH=/opt/romm"
ExecStart=/opt/romm/.venv/bin/python main.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/romm-worker.service
[Unit]
Description=RomM RQ Worker
After=network.target mariadb.service redis-server.service romm-backend.service
Requires=mariadb.service redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/romm/backend
EnvironmentFile=/opt/romm/.env
Environment="PYTHONPATH=/opt/romm/backend"
ExecStart=/opt/romm/.venv/bin/rq worker --with-scheduler --path /opt/romm/backend --url redis://127.0.0.1:6379/0 high default low
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/romm-scan-worker.service
[Unit]
Description=RomM RQ Scan Worker
After=network.target mariadb.service redis-server.service romm-backend.service
Requires=mariadb.service redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/romm/backend
EnvironmentFile=/opt/romm/.env
Environment="PYTHONPATH=/opt/romm/backend"
ExecStart=/opt/romm/.venv/bin/rq worker --with-scheduler --path /opt/romm/backend --url redis://127.0.0.1:6379/0 scans
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/romm-scheduler.service
[Unit]
Description=RomM RQ Scheduler
After=network.target mariadb.service redis-server.service romm-backend.service
Requires=mariadb.service redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/romm/backend
EnvironmentFile=/opt/romm/.env
Environment="PYTHONPATH=/opt/romm/backend"
ExecStart=/opt/romm/.venv/bin/rq cron --path /opt/romm/backend --url redis://127.0.0.1:6379/0 tasks.cron_config
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/romm-watcher.service
[Unit]
Description=RomM Filesystem Watcher
After=network.target romm-backend.service
Requires=romm-backend.service

[Service]
Type=simple
WorkingDirectory=/opt/romm/backend
EnvironmentFile=/opt/romm/.env
Environment="PYTHONPATH=/opt/romm/backend"
ExecStart=/opt/romm/.venv/bin/watchfiles --target-type command '/opt/romm/.venv/bin/python watcher.py' /var/lib/romm/library
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl enable -q --now romm-backend romm-worker romm-scan-worker romm-scheduler romm-watcher
  msg_ok "Created Services"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  check_available_storage_bytes "$var_lxc_romm_minimum_free_bytes" \
    /opt/romm /var/lib /var/cache "${HOME:-/root}" "${TMPDIR:-/tmp}" || return 252
  header_info
  check_container_storage
  check_container_resources

  _recover_update_backups "${BACKUP_DIR:-/opt/${NSAPP:-${APP_SLUG:-app}}.backup}" /opt/romm-players.backup || return $?

  if [[ ! -d /opt/romm ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="24" setup_nodejs || return $?

  local services=(romm-backend romm-worker romm-scheduler romm-watcher)
  local restart_services=false
  if [[ -f /etc/systemd/system/romm-scan-worker.service ]]; then
    services+=(romm-scan-worker)
  fi

  if check_for_gh_release "romm" "rommapp/romm"; then
    msg_info "Stopping Services"
    _update_services_stop romm "${services[@]}" || return $?
    msg_ok "Stopped Services"

    create_backup /opt/romm/.env || return $?
    BACKUP_DIR=/opt/romm-players.backup create_backup \
      /opt/romm/frontend/dist/assets/emulatorjs \
      /opt/romm/frontend/dist/assets/ruffle || return $?

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "romm" "rommapp/romm" "tarball" "latest" "/opt/romm" || return $?
    PYTHON_VERSION="3.13" UV_PROJECT_DIR="/opt/romm" setup_uv || return $?

    restore_backup || return $?

    msg_info "Updating ROMM"
    cd /opt/romm || exit
    $STD uv sync --all-extras || return $?
    cd /opt/romm/backend || exit
    $STD uv run alembic upgrade head || return $?
    if [[ -f /opt/romm/backend/utils/rom_patcher/package.json ]]; then
      cd /opt/romm/backend/utils/rom_patcher || exit
      $STD npm install --ignore-scripts --no-audit --no-fund || return $?
      if [[ -d node_modules/rom-patcher/rom-patcher-js ]]; then
        rm -rf rom-patcher-js || return $?
        cp -r node_modules/rom-patcher/rom-patcher-js ./rom-patcher-js || return $?
      fi
      rm -rf node_modules || return $?
    fi
    cd /opt/romm/frontend || exit
    $STD npm install || return $?
    $STD npm run build || return $?
    cp -rf /opt/romm/frontend/assets/* /opt/romm/frontend/dist/assets/ || return $?
    # Restore the player payloads after Vite has finished clearing/building dist.
    BACKUP_DIR=/opt/romm-players.backup restore_backup || return $?
    mkdir -p /opt/romm/frontend/dist/assets/romm || return $?
    ROMM_BASE=$(grep '^ROMM_BASE_PATH=' /opt/romm/.env | cut -d'=' -f2)
    ROMM_BASE=${ROMM_BASE:-/var/lib/romm}
    ln -sfn "$ROMM_BASE"/resources /opt/romm/frontend/dist/assets/romm/resources
    ln -sfn "$ROMM_BASE"/assets /opt/romm/frontend/dist/assets/romm/assets
    if [[ -f /etc/angie/http.d/romm.conf ]]; then
      sed -i "s|alias .*/library/;|alias ${ROMM_BASE}/library/;|" /etc/angie/http.d/romm.conf
      systemctl reload angie
    elif [[ -f /etc/nginx/sites-available/romm ]]; then
      sed -i "s|alias .*/library/;|alias ${ROMM_BASE}/library/;|" /etc/nginx/sites-available/romm
      systemctl reload nginx
    fi
    msg_ok "Updated ROMM"
    restart_services=true
  else
    local romm_release_status=$?
    [[ "$romm_release_status" == 1 ]] || return "$romm_release_status"
  fi

  # Repair already-current 5.3 installations as well as actual release upgrades.
  if [[ -f /opt/romm/backend/tasks/cron_config.py ]] && {
    grep -q 'bin/rqscheduler' /etc/systemd/system/romm-scheduler.service ||
      [[ ! -f /etc/systemd/system/romm-scan-worker.service ]]
  }; then
    msg_info "Migrating RQ Services"
    _update_services_stop romm romm-worker romm-scheduler || return $?
    sed -i -e '/Environment="RQ_REDIS_HOST=/d' \
      -e '/Environment="RQ_REDIS_PORT=/d' \
      -e 's|^ExecStart=.*|ExecStart=/opt/romm/.venv/bin/rq cron --path /opt/romm/backend --url redis://127.0.0.1:6379/0 tasks.cron_config|' \
      /etc/systemd/system/romm-scheduler.service
    sed -i 's|bin/rq worker --path|bin/rq worker --with-scheduler --path|' \
      /etc/systemd/system/romm-worker.service
    if [[ ! -f /etc/systemd/system/romm-scan-worker.service ]]; then
      sed -e 's|^Description=.*|Description=RomM RQ Scan Worker|' \
        -e 's|^ExecStart=.*|ExecStart=/opt/romm/.venv/bin/rq worker --with-scheduler --path /opt/romm/backend --url redis://127.0.0.1:6379/0 scans|' \
        /etc/systemd/system/romm-worker.service > /etc/systemd/system/romm-scan-worker.service
      services+=(romm-scan-worker)
    fi
    systemctl daemon-reload
    systemctl enable -q romm-scan-worker
    restart_services=true
    msg_ok "Migrated RQ Services"
  fi

  # A version marker alone does not prove the built frontend still has its files.
  if [[ ! -s /opt/romm/frontend/dist/assets/ruffle/ruffle.js ]]; then
    FORCE_DEPLOY=1 CLEAN_INSTALL=0 fetch_and_deploy_gh_release "ruffle" "ruffle-rs/ruffle" "prebuild" "latest" "/opt/romm/frontend/dist/assets/ruffle" "ruffle-*-web-selfhosted.zip" || return $?
    restart_services=true
  fi
  local emulatorjs_status
  if check_for_gh_release "EmulatorJS" "EmulatorJS/EmulatorJS" "v4.2.3"; then emulatorjs_status=0; else emulatorjs_status=$?; fi
  [[ "$emulatorjs_status" == 0 || "$emulatorjs_status" == 1 ]] || return "$emulatorjs_status"
  if [[ ! -s /opt/romm/frontend/dist/assets/emulatorjs/data/loader.js || ! -d /opt/romm/frontend/dist/assets/emulatorjs/data/cores || "$emulatorjs_status" == 0 ]]; then
    FORCE_DEPLOY=1 CLEAN_INSTALL=0 fetch_and_deploy_gh_release "EmulatorJS" "EmulatorJS/EmulatorJS" "prebuild" "v4.2.3" "/opt/romm/frontend/dist/assets/emulatorjs" "4.2.3.7z" || return $?
    restart_services=true
    msg_ok "Updated EmulatorJS successfully"
  fi

  if [[ ! -s /opt/romm/frontend/dist/assets/emulatorjs/data/loader.js || ! -s /opt/romm/frontend/dist/assets/ruffle/ruffle.js ]]; then
    msg_error "Player payloads are missing from the built frontend"
    exit 1
  fi
  if [[ "$restart_services" == true ]]; then
    msg_info "Starting Services"
    systemctl restart "${services[@]}" || return $?
    msg_ok "Started Services"
    msg_ok "Updated successfully"
  fi
  _update_services_finish romm || return $?
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
