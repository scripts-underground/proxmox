#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/FuzzyGrim/Yamtrack

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Yamtrack"
var_tags="${var_tags:-media;tracker;movies;anime}"
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
    redis-server
  msg_ok "Installed Dependencies"

  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="yamtrack" PG_DB_USER="yamtrack" setup_postgresql_db
  PYTHON_VERSION="3.12" setup_uv

  fetch_and_deploy_gh_release "yamtrack" "FuzzyGrim/Yamtrack" "tarball"

  msg_info "Installing Python Dependencies"
  cd /opt/yamtrack || exit
  $STD uv sync --locked
  msg_ok "Installed Python Dependencies"

  msg_info "Configuring Yamtrack"
  SECRET=$(openssl rand -hex 32)
  cat << EOF > /opt/yamtrack/src/.env
SECRET=${SECRET}
DB_HOST=localhost
DB_NAME=${PG_DB_NAME}
DB_USER=${PG_DB_USER}
DB_PASSWORD=${PG_DB_PASS}
DB_PORT=5432
REDIS_URL=redis://localhost:6379
URLS=http://${LOCAL_IP}:8000
EOF

  cd /opt/yamtrack/src || exit
  $STD /opt/yamtrack/.venv/bin/python manage.py migrate
  $STD /opt/yamtrack/.venv/bin/python manage.py collectstatic --noinput
  msg_ok "Configured Yamtrack"

  msg_info "Configuring Nginx"
  rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default
  cp /opt/yamtrack/nginx.conf /etc/nginx/nginx.conf
  sed -i 's|user abc;|user www-data;|' /etc/nginx/nginx.conf
  sed -i 's|pid /tmp/nginx.pid;|pid /run/nginx.pid;|' /etc/nginx/nginx.conf
  sed -i 's|/yamtrack/staticfiles/|/opt/yamtrack/src/staticfiles/|' /etc/nginx/nginx.conf
  sed -i 's|error_log /dev/stderr|error_log /var/log/nginx/error.log|' /etc/nginx/nginx.conf
  sed -i 's|access_log /dev/stdout|access_log /var/log/nginx/access.log|' /etc/nginx/nginx.conf
  $STD nginx -t
  systemctl enable -q nginx
  $STD systemctl restart nginx
  msg_ok "Configured Nginx"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/yamtrack.service
[Unit]
Description=Yamtrack Gunicorn
After=network.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/yamtrack/src
ExecStart=/opt/yamtrack/.venv/bin/gunicorn config.wsgi:application -b 127.0.0.1:8001 -w 2 --timeout 120
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/yamtrack-celery.service
[Unit]
Description=Yamtrack Celery Worker
After=network.target postgresql.service redis-server.service yamtrack.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/yamtrack/src
ExecStart=/opt/yamtrack/.venv/bin/celery -A config worker --beat --scheduler django --loglevel INFO
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl enable -q --now redis-server yamtrack yamtrack-celery
  msg_ok "Created Services"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/yamtrack ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "yamtrack" "FuzzyGrim/Yamtrack"; then
    msg_info "Stopping Services"
    systemctl stop yamtrack yamtrack-celery
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    cp /opt/yamtrack/src/.env /opt/yamtrack_env.bak
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "yamtrack" "FuzzyGrim/Yamtrack" "tarball"

    msg_info "Installing Python Dependencies"
    cd /opt/yamtrack || exit
    $STD uv sync --locked
    msg_ok "Installed Python Dependencies"

    msg_info "Restoring Data"
    cp /opt/yamtrack_env.bak /opt/yamtrack/src/.env
    rm -f /opt/yamtrack_env.bak
    msg_ok "Restored Data"

    msg_info "Updating Yamtrack"
    cd /opt/yamtrack/src || exit
    $STD /opt/yamtrack/.venv/bin/python manage.py migrate
    $STD /opt/yamtrack/.venv/bin/python manage.py collectstatic --noinput
    msg_ok "Updated Yamtrack"

    msg_info "Updating Nginx Configuration"
    cp /opt/yamtrack/nginx.conf /etc/nginx/nginx.conf
    sed -i 's|user abc;|user www-data;|' /etc/nginx/nginx.conf
    sed -i 's|pid /tmp/nginx.pid;|pid /run/nginx.pid;|' /etc/nginx/nginx.conf
    sed -i 's|/yamtrack/staticfiles/|/opt/yamtrack/src/staticfiles/|' /etc/nginx/nginx.conf
    sed -i 's|error_log /dev/stderr|error_log /var/log/nginx/error.log|' /etc/nginx/nginx.conf
    sed -i 's|access_log /dev/stdout|access_log /var/log/nginx/access.log|' /etc/nginx/nginx.conf
    $STD systemctl reload nginx
    msg_ok "Updated Nginx Configuration"

    msg_info "Starting Services"
    systemctl start yamtrack yamtrack-celery
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
