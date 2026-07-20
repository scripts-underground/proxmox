#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (MickLesk)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://linkding.link/

# shellcheck disable=SC2034
APP="linkding"
var_tags="${var_tags:-bookmarks;management}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    pkg-config \
    python3-dev \
    nginx \
    libpq-dev \
    libicu-dev \
    libsqlite3-dev \
    libffi-dev
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" setup_nodejs
  setup_uv
  fetch_and_deploy_gh_release "linkding" "sissbruecker/linkding" "tarball"

  msg_info "Building Frontend"
  cd /opt/linkding || exit
  $STD npm ci
  $STD npm run build
  LINK_ARCH="x86_64-linux-gnu"
  [[ "$(get_system_arch)" == "arm64" ]] && LINK_ARCH="aarch64-linux-gnu"
  ln -sf /usr/lib/${LINK_ARCH}/mod_icu.so /opt/linkding/libicu.so
  msg_ok "Built Frontend"

  msg_info "Setting up LinkDing"
  rm -f bookmarks/settings/dev.py
  touch bookmarks/settings/custom.py
  $STD uv sync --no-dev --frozen
  $STD uv pip install gunicorn
  mkdir -p data/{favicons,previews,assets}
  ADMIN_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
  cat << EOF > /opt/linkding/.env
LD_SUPERUSER_NAME=admin
LD_SUPERUSER_PASSWORD=${ADMIN_PASS}
LD_CSRF_TRUSTED_ORIGINS=http://${LOCAL_IP}:9090
EOF
  set -a && source /opt/linkding/.env && set +a
  $STD /opt/linkding/.venv/bin/python manage.py generate_secret_key
  $STD /opt/linkding/.venv/bin/python manage.py migrate
  $STD /opt/linkding/.venv/bin/python manage.py enable_wal
  $STD /opt/linkding/.venv/bin/python manage.py create_initial_superuser
  $STD /opt/linkding/.venv/bin/python manage.py collectstatic --no-input
  msg_ok "Set up LinkDing"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/linkding.service
[Unit]
Description=linkding Bookmark Manager
After=network.target

[Service]
User=root
WorkingDirectory=/opt/linkding
EnvironmentFile=/opt/linkding/.env
ExecStart=/opt/linkding/.venv/bin/gunicorn \
  --bind 127.0.0.1:8000 \
  --workers 3 \
  --threads 2 \
  --timeout 120 \
  bookmarks.wsgi:application
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  cat << EOF > /etc/systemd/system/linkding-tasks.service
[Unit]
Description=linkding Background Tasks
After=network.target

[Service]
User=root
WorkingDirectory=/opt/linkding
EnvironmentFile=/opt/linkding/.env
ExecStart=/opt/linkding/.venv/bin/python manage.py run_huey
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  cat << 'EOF' > /etc/nginx/sites-available/linkding
server {
    listen 9090;
    server_name _;

    client_max_body_size 20M;

    location /static/ {
        alias /opt/linkding/static/;
        expires 30d;
    }

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_redirect off;
    }
}
EOF
  $STD rm -f /etc/nginx/sites-enabled/default
  $STD ln -sf /etc/nginx/sites-available/linkding /etc/nginx/sites-enabled/linkding
  systemctl enable -q --now nginx linkding linkding-tasks
  systemctl restart nginx
  msg_ok "Created Services"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:9090${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/linkding ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "linkding" "sissbruecker/linkding"; then
    msg_info "Stopping Services"
    systemctl stop nginx linkding linkding-tasks
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    cp -r /opt/linkding/data /opt/linkding_data_backup
    cp /opt/linkding/.env /opt/linkding_env_backup
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "linkding" "sissbruecker/linkding" "tarball"

    msg_info "Restoring Data"
    cp -r /opt/linkding_data_backup/. /opt/linkding/data
    cp /opt/linkding_env_backup /opt/linkding/.env
    rm -rf /opt/linkding_data_backup /opt/linkding_env_backup
    LINK_ARCH="x86_64-linux-gnu"
    [[ "$(get_system_arch)" == "arm64" ]] && LINK_ARCH="aarch64-linux-gnu"
    ln -sf /usr/lib/${LINK_ARCH}/mod_icu.so /opt/linkding/libicu.so
    msg_ok "Restored Data"

    msg_info "Updating LinkDing"
    cd /opt/linkding || exit
    rm -f bookmarks/settings/dev.py
    touch bookmarks/settings/custom.py
    $STD npm ci
    $STD npm run build
    $STD uv sync --no-dev --frozen
    $STD uv pip install gunicorn
    set -a && source /opt/linkding/.env && set +a
    $STD /opt/linkding/.venv/bin/python manage.py migrate
    $STD /opt/linkding/.venv/bin/python manage.py collectstatic --no-input
    msg_ok "Updated LinkDing"

    msg_info "Starting Services"
    systemctl start nginx linkding linkding-tasks
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
