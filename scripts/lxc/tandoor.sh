#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://tandoor.dev/

# shellcheck disable=SC2034
APP="Tandoor"
var_tags="${var_tags:-recipes}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    python3 \
    libpq-dev \
    libmagic-dev \
    libzbar0 \
    nginx \
    libsasl2-dev \
    libldap2-dev \
    libssl-dev \
    pkg-config \
    libxmlsec1-dev \
    libxml2-dev \
    libxmlsec1-openssl
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs
  fetch_and_deploy_gh_release "tandoor" "TandoorRecipes/recipes" "tarball" "latest" "/opt/tandoor"
  PG_VERSION="17" setup_postgresql
  PYTHON_VERSION="3.13" setup_uv
  PG_DB_USER="tandoor" PG_DB_NAME="db_recipes" PG_DB_EXTENSIONS="unaccent,pg_trgm" setup_postgresql_db
  SECRET_KEY=$(openssl rand -base64 45 | sed 's/\//\\\//g')

  msg_info "Setup Tandoor"
  mkdir -p /opt/tandoor/{config,api,mediafiles,staticfiles}
  cd /opt/tandoor || exit
  $STD uv venv --clear .venv --python=python3
  $STD uv pip install -r requirements.txt --python .venv/bin/python
  cd /opt/tandoor/vue3 || exit
  $STD yarn install
  $STD yarn build
  cat << EOF > /opt/tandoor/.env
SECRET_KEY=$SECRET_KEY
ALLOWED_HOSTS=$LOCAL_IP
TZ=Europe/Berlin

DB_ENGINE=django.db.backends.postgresql
POSTGRES_HOST=localhost
POSTGRES_DB=$PG_DB_NAME
POSTGRES_PORT=5432
POSTGRES_USER=$PG_DB_USER
POSTGRES_PASSWORD=$PG_DB_PASS

STATIC_URL=/staticfiles/
MEDIA_URL=/media/
EOF

  TANDOOR_VERSION=$(get_latest_github_release "TandoorRecipes/recipes")
  cat << EOF > /opt/tandoor/cookbook/version_info.py
TANDOOR_VERSION = "$TANDOOR_VERSION"
TANDOOR_REF = "bare-metal"
VERSION_INFO = []
EOF

  cd /opt/tandoor || exit
  $STD /opt/tandoor/.venv/bin/python manage.py migrate
  $STD /opt/tandoor/.venv/bin/python manage.py collectstatic --no-input
  msg_ok "Installed Tandoor"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/tandoor.service
[Unit]
Description=gunicorn daemon for tandoor
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=3
WorkingDirectory=/opt/tandoor
EnvironmentFile=/opt/tandoor/.env
ExecStart=/opt/tandoor/.venv/bin/gunicorn --error-logfile /tmp/gunicorn_err.log --log-level debug --capture-output --bind unix:/opt/tandoor/tandoor.sock recipes.wsgi:application

[Install]
WantedBy=multi-user.target
EOF

  cat << 'EOF' > /etc/nginx/conf.d/tandoor.conf
server {
    listen 8002;
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    client_max_body_size 128M;
    # serve media files
    location /static/ {
        alias /opt/tandoor/staticfiles/;
    }

    location /media/ {
        alias /opt/tandoor/mediafiles/;
    }

    location / {
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
        proxy_pass http://unix:/opt/tandoor/tandoor.sock;
    }
}
EOF
  systemctl reload nginx
  systemctl enable -q --now tandoor
  msg_ok "Created Services"

  touch ~/.tandoor
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8002${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/tandoor ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if [[ ! -f ~/.tandoor ]]; then
    msg_error "v1 Installation found, please export your data and create an new LXC."
    exit
  fi

  if ! grep -q "^ALLOWED_HOSTS=" /opt/tandoor/.env; then
    echo "ALLOWED_HOSTS=${LOCAL_IP}" >> /opt/tandoor/.env
  fi

  if check_for_gh_release "tandoor" "TandoorRecipes/recipes"; then
    msg_info "Stopping Service"
    systemctl stop tandoor
    msg_ok "Stopped Service"

    msg_info "Creating Backup"
    mv /opt/tandoor /opt/tandoor.bak
    msg_ok "Backup Created"

    NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs
    PYTHON_VERSION="3.13" setup_uv
    fetch_and_deploy_gh_release "tandoor" "TandoorRecipes/recipes" "tarball" "latest" "/opt/tandoor"

    msg_info "Updating Tandoor"
    cp -r /opt/tandoor.bak/{config,api,mediafiles,staticfiles} /opt/tandoor/
    mv /opt/tandoor.bak/.env /opt/tandoor/.env
    cd /opt/tandoor || exit
    $STD uv venv --clear .venv --python=python3
    $STD uv pip install -r requirements.txt --python .venv/bin/python
    cd /opt/tandoor/vue3 || exit
    $STD yarn install
    $STD yarn build
    TANDOOR_VERSION=$(get_latest_github_release "TandoorRecipes/recipes")
    cat << EOF > /opt/tandoor/cookbook/version_info.py
TANDOOR_VERSION = "$TANDOOR_VERSION"
TANDOOR_REF = "bare-metal"
VERSION_INFO = []
EOF
    cd /opt/tandoor || exit
    $STD /opt/tandoor/.venv/bin/python manage.py migrate
    $STD /opt/tandoor/.venv/bin/python manage.py collectstatic --no-input
    rm -rf /opt/tandoor.bak
    msg_ok "Updated Tandoor"

    msg_info "Starting Service"
    systemctl start tandoor
    systemctl reload nginx
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
