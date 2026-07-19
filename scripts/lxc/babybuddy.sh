#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/babybuddy/babybuddy

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Baby Buddy"
var_tags="${var_tags:-baby}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    uwsgi \
    uwsgi-plugin-python3 \
    libopenjp2-7-dev \
    libpq-dev \
    nginx \
    python3
  msg_ok "Installed Dependencies"

  setup_uv
  fetch_and_deploy_gh_release "babybuddy" "babybuddy/babybuddy" "tarball"

  msg_info "Installing Baby Buddy"
  mkdir -p /opt/data
  cd /opt/babybuddy || exit
  $STD uv venv --clear .venv
  $STD source .venv/bin/activate
  $STD uv pip install -r requirements.txt
  cp babybuddy/settings/production.example.py babybuddy/settings/production.py
  SECRET_KEY=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | cut -c1-32)
  ALLOWED_HOSTS=$(hostname -I | tr ' ' ',' | sed 's/,$//')",127.0.0.1,localhost"
  sed -i \
    -e "s/^SECRET_KEY = \"\"/SECRET_KEY = \"$SECRET_KEY\"/" \
    -e "s/^ALLOWED_HOSTS = \[\"\"\]/ALLOWED_HOSTS = \[$(echo \"$ALLOWED_HOSTS\" | sed 's/,/\",\"/g')\]/" \
    babybuddy/settings/production.py

  export DJANGO_SETTINGS_MODULE=babybuddy.settings.production
  $STD python manage.py migrate
  chown -R www-data:www-data /opt/data
  chmod 640 /opt/data/db.sqlite3
  chmod 750 /opt/data
  msg_ok "Installed Baby Buddy"

  msg_info "Configuring uWSGI"
  cat << EOF > /etc/uwsgi/apps-available/babybuddy.ini
[uwsgi]
plugins = python3
project = babybuddy
base_dir = /opt/babybuddy
chdir = %(base_dir)
virtualenv = %(base_dir)/.venv
module = %(project).wsgi:application
env = DJANGO_SETTINGS_MODULE=%(project).settings.production
master = True
vacuum = True
socket = /var/run/uwsgi/app/babybuddy/socket
chmod-socket = 660
uid = www-data
gid = www-data
EOF
  ln -sf /etc/uwsgi/apps-available/babybuddy.ini /etc/uwsgi/apps-enabled/babybuddy.ini
  service uwsgi restart
  msg_ok "Configured uWSGI"

  msg_info "Configuring NGINX"
  cat << EOF > /etc/nginx/sites-available/babybuddy
upstream babybuddy {
    server unix:///var/run/uwsgi/app/babybuddy/socket;
}

server {
    listen 80;
    server_name _;

    location / {
        uwsgi_pass babybuddy;
        include uwsgi_params;
    }

    location /media {
        alias /opt/data/media;
    }
}
EOF

  ln -sf /etc/nginx/sites-available/babybuddy /etc/nginx/sites-enabled/babybuddy
  rm /etc/nginx/sites-enabled/default
  systemctl enable -q --now nginx
  service nginx reload
  msg_ok "Configured NGINX"
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
  if [[ ! -d /opt/babybuddy ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "babybuddy" "babybuddy/babybuddy"; then
    setup_uv

    msg_info "Stopping Services"
    systemctl stop nginx
    systemctl stop uwsgi
    msg_ok "Services Stopped"

    create_backup /opt/babybuddy/babybuddy/settings/production.py

    msg_info "Cleaning old files"
    cd /opt/babybuddy || exit || exit
    find . -mindepth 1 -maxdepth 1 ! -name '.venv' -exec rm -rf -- {} +
    msg_ok "Cleaned old files"

    fetch_and_deploy_gh_release "babybuddy" "babybuddy/babybuddy" "tarball"
    restore_backup

    msg_info "Updating ${APP}"
    cd /opt/babybuddy || exit
    source .venv/bin/activate
    $STD uv pip install -r requirements.txt
    export DJANGO_SETTINGS_MODULE=babybuddy.settings.production
    $STD python manage.py makemigrations
    $STD python manage.py migrate
    msg_ok "Updated ${APP}"

    msg_info "Fixing permissions"
    chown -R www-data:www-data /opt/data
    chmod 640 /opt/data/db.sqlite3
    chmod 750 /opt/data
    msg_ok "Permissions fixed"

    msg_info "Starting Services"
    systemctl start uwsgi
    systemctl start nginx
    msg_ok "Services Started"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
