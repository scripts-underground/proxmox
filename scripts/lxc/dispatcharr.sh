#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: ekke85 | MickLesk
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Dispatcharr/Dispatcharr

# shellcheck disable=SC2034
APP="Dispatcharr"
var_tags="${var_tags:-media;arr}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_gpu="${var_gpu:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    python3-dev \
    libpq-dev \
    nginx \
    redis-server \
    ffmpeg \
    procps \
    vlc-bin \
    vlc-plugin-base \
    streamlink
  msg_ok "Installed Dependencies"

  setup_uv
  NODE_VERSION="24" setup_nodejs
  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="dispatcharr_db" PG_DB_USER="dispatcharr_usr" setup_postgresql_db
  setup_hwaccel
  fetch_and_deploy_gh_release "dispatcharr" "Dispatcharr/Dispatcharr" "tarball"

  msg_info "Installing Python Dependencies with uv"
  cd /opt/dispatcharr || exit
  $STD uv venv --clear
  $STD uv sync
  $STD uv pip install uwsgi gevent celery redis daphne
  msg_ok "Installed Python Dependencies"

  msg_info "Configuring Dispatcharr"
  install -d -m 755 \
    /data/{logos,recordings,plugins,db} \
    /data/uploads/{m3us,epgs} \
    /data/{m3us,epgs}
  chown -R root:root /data
  DJANGO_SECRET=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | cut -c1-50)
  export DATABASE_URL="postgresql://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}"
  export POSTGRES_DB=$PG_DB_NAME
  export POSTGRES_USER=$PG_DB_USER
  export POSTGRES_PASSWORD=$PG_DB_PASS
  export POSTGRES_HOST=localhost
  export DJANGO_SECRET_KEY=$DJANGO_SECRET
  $STD uv run python manage.py migrate --noinput
  $STD uv run python manage.py collectstatic --noinput
  cat << EOF > /opt/dispatcharr/.env
DATABASE_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}
POSTGRES_DB=$PG_DB_NAME
POSTGRES_USER=$PG_DB_USER
POSTGRES_PASSWORD=$PG_DB_PASS
POSTGRES_HOST=localhost
CELERY_BROKER_URL=redis://localhost:6379/0
DJANGO_SECRET_KEY=$DJANGO_SECRET
EOF
  cd /opt/dispatcharr/frontend || exit
  node -e "const p=require('./package.json');p.overrides=p.overrides||{};p.overrides['webworkify-webpack']='2.1.3';require('fs').writeFileSync('package.json',JSON.stringify(p,null,2));"
  rm -f package-lock.json
  $STD npm install --no-audit --progress=false
  $STD npm run build
  msg_ok "Configured Dispatcharr"

  msg_info "Configuring Nginx"
  cat << EOF > /etc/nginx/sites-available/dispatcharr.conf
map \$http_x_forwarded_proto \$real_forwarded_proto {
    ""      \$scheme;
    default \$http_x_forwarded_proto;
}

map \$http_x_forwarded_port \$real_forwarded_port {
    ""      \$server_port;
    default \$http_x_forwarded_port;
}

server {
    listen 9191;
    server_name _;
    client_max_body_size 100M;

    location /assets/ {
        alias /opt/dispatcharr/frontend/dist/assets/;
        expires 30d;
        add_header Cache-Control "public, immutable";

        types {
            text/javascript js;
            text/css css;
            image/png png;
            image/svg+xml svg svgz;
            font/woff2 woff2;
            font/woff woff;
            font/ttf ttf;
        }
    }

    location /static/ {
        alias /opt/dispatcharr/static/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    location /media/ {
        alias /opt/dispatcharr/media/;
    }

    location /ws/ {
        proxy_pass http://127.0.0.1:8001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$real_forwarded_proto;
    }

    location / {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$real_forwarded_proto;
        proxy_set_header X-Forwarded-Port \$real_forwarded_port;
        proxy_pass http://127.0.0.1:5656;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/dispatcharr.conf /etc/nginx/sites-enabled/dispatcharr.conf
  rm -f /etc/nginx/sites-enabled/default
  systemctl restart nginx
  msg_ok "Configured Nginx"

  msg_info "Creating Services"
  cat << EOF > /opt/dispatcharr/start-uwsgi.sh
#!/usr/bin/env bash
cd /opt/dispatcharr
set -a
source .env
set +a
exec .venv/bin/uwsgi \
    --chdir=/opt/dispatcharr \
    --module=dispatcharr.wsgi:application \
    --master \
    --workers=4 \
    --gevent=400 \
    --http=0.0.0.0:5656 \
    --http-keepalive=1 \
    --http-timeout=600 \
    --socket-timeout=600 \
    --buffer-size=65536 \
    --post-buffering=4096 \
    --lazy-apps \
    --thunder-lock \
    --die-on-term \
    --vacuum
EOF
  chmod +x /opt/dispatcharr/start-uwsgi.sh

  cat << EOF > /opt/dispatcharr/start-celery.sh
#!/usr/bin/env bash
cd /opt/dispatcharr
set -a
source .env
set +a
exec uv run celery -A dispatcharr worker -l info -c 4
EOF
  chmod +x /opt/dispatcharr/start-celery.sh

  cat << EOF > /opt/dispatcharr/start-celerybeat.sh
#!/usr/bin/env bash
cd /opt/dispatcharr
set -a
source .env
set +a
exec uv run celery -A dispatcharr beat -l info
EOF
  chmod +x /opt/dispatcharr/start-celerybeat.sh

  cat << EOF > /opt/dispatcharr/start-daphne.sh
#!/usr/bin/env bash
cd /opt/dispatcharr
set -a
source .env
set +a
exec uv run daphne -b 0.0.0.0 -p 8001 dispatcharr.asgi:application
EOF
  chmod +x /opt/dispatcharr/start-daphne.sh

  cat << EOF > /etc/systemd/system/dispatcharr.service
[Unit]
Description=Dispatcharr Web Server
After=network.target postgresql.service redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/dispatcharr
ExecStart=/opt/dispatcharr/start-uwsgi.sh
Restart=on-failure
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/dispatcharr-celery.service
[Unit]
Description=Dispatcharr Celery Worker
After=network.target redis-server.service
Requires=dispatcharr.service

[Service]
Type=simple
WorkingDirectory=/opt/dispatcharr
ExecStart=/opt/dispatcharr/start-celery.sh
Restart=on-failure
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/dispatcharr-celerybeat.service
[Unit]
Description=Dispatcharr Celery Beat Scheduler
After=network.target redis-server.service
Requires=dispatcharr.service

[Service]
Type=simple
WorkingDirectory=/opt/dispatcharr
ExecStart=/opt/dispatcharr/start-celerybeat.sh
Restart=on-failure
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/dispatcharr-daphne.service
[Unit]
Description=Dispatcharr WebSocket Server (Daphne)
After=network.target
Requires=dispatcharr.service

[Service]
Type=simple
WorkingDirectory=/opt/dispatcharr
ExecStart=/opt/dispatcharr/start-daphne.sh
Restart=on-failure
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now dispatcharr dispatcharr-celery dispatcharr-celerybeat dispatcharr-daphne
  msg_ok "Created Services"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:9191${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d "/opt/dispatcharr" ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  setup_uv
  NODE_VERSION="24" setup_nodejs
  if [[ -f "/etc/nginx/sites-available/dispatcharr.conf" ]] && ! grep -q "real_forwarded_proto" "/etc/nginx/sites-available/dispatcharr.conf"; then
    msg_info "Migrating Nginx Configuration"
    cat << EOF > "/etc/nginx/sites-available/dispatcharr.conf"
map \$http_x_forwarded_proto \$real_forwarded_proto {
    ""      \$scheme;
    default \$http_x_forwarded_proto;
}

map \$http_x_forwarded_port \$real_forwarded_port {
    ""      \$server_port;
    default \$http_x_forwarded_port;
}

server {
    listen 9191;
    server_name _;
    client_max_body_size 100M;

    location /assets/ {
        alias /opt/dispatcharr/frontend/dist/assets/;
        expires 30d;
        add_header Cache-Control "public, immutable";

        types {
            text/javascript js;
            text/css css;
            image/png png;
            image/svg+xml svg svgz;
            font/woff2 woff2;
            font/woff woff;
            font/ttf ttf;
        }
    }

    location /static/ {
        alias /opt/dispatcharr/static/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    location /media/ {
        alias /opt/dispatcharr/media/;
    }

    location /ws/ {
        proxy_pass http://127.0.0.1:8001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$real_forwarded_proto;
    }

    location / {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$real_forwarded_proto;
        proxy_set_header X-Forwarded-Port \$real_forwarded_port;
        proxy_pass http://127.0.0.1:5656;
    }
}
EOF
    systemctl reload nginx
    msg_ok "Migrated Nginx Configuration"
  fi

  ensure_dependencies vlc-bin vlc-plugin-base

  if check_for_gh_release "Dispatcharr" "Dispatcharr/Dispatcharr"; then
    msg_info "Stopping Services"
    systemctl stop dispatcharr-celery
    systemctl stop dispatcharr-celerybeat
    systemctl stop dispatcharr-daphne
    systemctl stop dispatcharr
    msg_ok "Stopped Services"

    msg_info "Creating Backup"
    BACKUP_FILE="/opt/dispatcharr_backup_$(date +%F_%H-%M-%S).tar.gz"
    if [[ -f /opt/dispatcharr/.env ]]; then
      cp /opt/dispatcharr/.env /tmp/dispatcharr.env.backup
    fi
    if [[ -f /opt/dispatcharr/start-gunicorn.sh ]]; then
      rm -f /opt/dispatcharr/start-gunicorn.sh
    fi
    if [[ -f /opt/dispatcharr/start-celery.sh ]]; then
      cp /opt/dispatcharr/start-celery.sh /tmp/start-celery.sh.backup
    fi
    if [[ -f /opt/dispatcharr/start-celerybeat.sh ]]; then
      cp /opt/dispatcharr/start-celerybeat.sh /tmp/start-celerybeat.sh.backup
    fi
    if [[ -f /opt/dispatcharr/start-daphne.sh ]]; then
      cp /opt/dispatcharr/start-daphne.sh /tmp/start-daphne.sh.backup
    fi
    if [[ -f /opt/dispatcharr/.env ]]; then
      set -o allexport
      source /opt/dispatcharr/.env
      set +o allexport
      if [[ -n "$POSTGRES_DB" ]] && [[ -n "$POSTGRES_USER" ]] && [[ -n "$POSTGRES_PASSWORD" ]]; then
        PGPASSWORD=$POSTGRES_PASSWORD pg_dump -U "$POSTGRES_USER" -h "${POSTGRES_HOST:-localhost}" -p "${POSTGRES_PORT:-5432}" "$POSTGRES_DB" > "/tmp/dispatcharr_db_$(date +%F).sql"
        msg_info "Database backup created"
      fi
    fi
    $STD tar -czf "$BACKUP_FILE" -C /opt dispatcharr /tmp/dispatcharr_db_*.sql
    msg_ok "Backup created: $BACKUP_FILE"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "dispatcharr" "Dispatcharr/Dispatcharr" "tarball"

    msg_info "Updating Dispatcharr Backend"
    if [[ -f /tmp/dispatcharr.env.backup ]]; then
      mv /tmp/dispatcharr.env.backup /opt/dispatcharr/.env
    fi
    if [[ -f /tmp/start-celery.sh.backup ]]; then
      mv /tmp/start-celery.sh.backup /opt/dispatcharr/start-celery.sh
    fi
    if [[ -f /tmp/start-celerybeat.sh.backup ]]; then
      mv /tmp/start-celerybeat.sh.backup /opt/dispatcharr/start-celerybeat.sh
    fi
    if [[ -f /tmp/start-daphne.sh.backup ]]; then
      mv /tmp/start-daphne.sh.backup /opt/dispatcharr/start-daphne.sh
    fi

    if ! grep -q "DJANGO_SECRET_KEY" /opt/dispatcharr/.env; then
      DJANGO_SECRET=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | cut -c1-50)
      echo "DJANGO_SECRET_KEY=$DJANGO_SECRET" >> /opt/dispatcharr/.env
    fi

    cd /opt/dispatcharr || exit
    rm -rf .venv
    $STD uv venv --clear
    $STD uv sync
    $STD uv pip install uwsgi gevent celery redis daphne
    cat << 'EOF' > /opt/dispatcharr/start-uwsgi.sh
#!/usr/bin/env bash
cd /opt/dispatcharr
set -a
source .env
set +a
exec .venv/bin/uwsgi \
    --chdir=/opt/dispatcharr \
    --module=dispatcharr.wsgi:application \
    --master \
    --workers=4 \
    --gevent=400 \
    --http=0.0.0.0:5656 \
    --http-keepalive=1 \
    --http-timeout=600 \
    --socket-timeout=600 \
    --buffer-size=65536 \
    --post-buffering=4096 \
    --lazy-apps \
    --thunder-lock \
    --die-on-term \
    --vacuum
EOF
    chmod +x /opt/dispatcharr/start-uwsgi.sh
    if grep -q 'start-gunicorn.sh' /etc/systemd/system/dispatcharr.service; then
      sed -i 's|start-gunicorn.sh|start-uwsgi.sh|g' /etc/systemd/system/dispatcharr.service
      systemctl daemon-reload
    fi
    msg_ok "Updated Dispatcharr Backend"

    msg_info "Building Frontend"
    cd /opt/dispatcharr/frontend || exit
    node -e "const p=require('./package.json');p.overrides=p.overrides||{};p.overrides['webworkify-webpack']='2.1.3';require('fs').writeFileSync('package.json',JSON.stringify(p,null,2));"
    rm -f package-lock.json
    $STD npm install --no-audit --progress=false
    $STD npm run build
    msg_ok "Built Frontend"

    msg_info "Running Django Migrations"
    cd /opt/dispatcharr || exit
    if [[ -f .env ]]; then
      set -o allexport
      source .env
      set +o allexport
    fi
    $STD uv run python manage.py migrate --noinput
    $STD uv run python manage.py collectstatic --noinput
    rm -f /tmp/dispatcharr_db_*.sql
    msg_ok "Migrations Complete"

    msg_info "Starting Services"
    systemctl start dispatcharr
    systemctl start dispatcharr-celery
    systemctl start dispatcharr-celerybeat
    systemctl start dispatcharr-daphne
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
