#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://healthchecks.io/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="healthchecks"
var_tags="${var_tags:-monitoring}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    gcc \
    python3 \
    python3-dev \
    python3-venv \
    libpq-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    caddy
  mkdir -p ~/.config/pip
  cat > ~/.config/pip/pip.conf << EOF
[global]
break-system-packages = true
EOF
  msg_ok "Installed Dependencies"

  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="healthchecks_db" PG_DB_USER="hc_user" PG_DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13) setup_postgresql_db

  msg_info "Setup Keys (Admin / Secret)"
  SECRET_KEY="$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | cut -c1-32)"
  ADMIN_EMAIL="admin@community-scripts.org"
  ADMIN_PASSWORD="$PG_DB_PASS"
  cat << EOF > ~/healthchecks.creds
healthchecks Admin Email: $ADMIN_EMAIL
healthchecks Admin Password: $ADMIN_PASSWORD
EOF
  msg_ok "Set up Keys"

  fetch_and_deploy_gh_release "healthchecks" "healthchecks/healthchecks" "tarball"

  msg_info "Installing Healthchecks (venv)"
  cd /opt/healthchecks || exit
  python3 -m venv venv
  source venv/bin/activate

  $STD pip install --upgrade pip wheel
  $STD pip install gunicorn -r requirements.txt
  msg_ok "Installed Python packages"

  cat << EOF > /opt/healthchecks/hc/local_settings.py
DEBUG = False

ALLOWED_HOSTS = ["${LOCAL_IP}", "127.0.0.1", "localhost"]
CSRF_TRUSTED_ORIGINS = ["http://${LOCAL_IP}", "https://${LOCAL_IP}"]

SECRET_KEY = "${SECRET_KEY}"

SITE_ROOT = "http://${LOCAL_IP}:8000"
SITE_NAME = "MyChecks"
DEFAULT_FROM_EMAIL = "healthchecks@${LOCAL_IP}"

STATIC_ROOT = "/opt/healthchecks/static-collected"
COMPRESS_OFFLINE = True

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': '${PG_DB_NAME}',
        'USER': '${PG_DB_USER}',
        'PASSWORD': '${PG_DB_PASS}',
        'HOST': '127.0.0.1',
        'PORT': '5432',
        'TEST': {'CHARSET': 'UTF8'}
    }
}
EOF

  msg_info "Running Django setup"
  $STD python manage.py makemigrations
  $STD python manage.py migrate --noinput
  $STD python manage.py collectstatic --noinput
  $STD python manage.py compress

  $STD python manage.py shell << EOF
from django.contrib.auth import get_user_model
User = get_user_model()
if not User.objects.filter(email="${ADMIN_EMAIL}").exists():
    User.objects.create_superuser("${ADMIN_EMAIL}", "${ADMIN_EMAIL}", "${ADMIN_PASSWORD}")
EOF
  msg_ok "Configured Django"

  msg_info "Configuring Caddy"
  cat << EOF > /etc/caddy/Caddyfile
{
    email admin@example.com
}

${LOCAL_IP} {
    reverse_proxy 127.0.0.1:8000
}
EOF
  msg_ok "Configured Caddy"

  msg_info "Creating systemd services"
  cat << EOF > /etc/systemd/system/healthchecks.service
[Unit]
Description=Healthchecks Service
After=network.target postgresql.service

[Service]
WorkingDirectory=/opt/healthchecks/
ExecStart=/opt/healthchecks/venv/bin/gunicorn hc.wsgi:application --bind 127.0.0.1:8000
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/healthchecks-sendalerts.service
[Unit]
Description=Healthchecks Sendalerts Service
After=network.target postgresql.service healthchecks.service

[Service]
WorkingDirectory=/opt/healthchecks/
ExecStart=/opt/healthchecks/venv/bin/python manage.py sendalerts
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  systemctl enable -q --now healthchecks healthchecks-sendalerts caddy
  systemctl reload caddy
  msg_ok "Created Services"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}https://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/healthchecks ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "healthchecks" "healthchecks/healthchecks"; then
    msg_info "Stopping Services"
    systemctl stop healthchecks
    systemctl stop healthchecks-sendalerts
    msg_ok "Stopped Services"

    msg_info "Backing up existing installation"
    BACKUP="/opt/healthchecks-backup-$(date +%F-%H%M)"
    cp -a /opt/healthchecks "$BACKUP"
    msg_ok "Backup created at $BACKUP"

    fetch_and_deploy_gh_release "healthchecks" "healthchecks/healthchecks" "tarball"

    cd /opt/healthchecks || exit
    if [[ -d venv ]]; then
      rm -rf venv
    fi
    msg_info "Recreating Python venv"
    $STD python3 -m venv venv
    source venv/bin/activate
    $STD pip install --upgrade pip wheel
    msg_ok "Created venv"

    msg_info "Installing requirements"
    $STD pip install gunicorn -r requirements.txt
    msg_ok "Installed requirements"

    msg_info "Running Django migrations"
    $STD python manage.py migrate --noinput
    $STD python manage.py collectstatic --noinput
    $STD python manage.py compress
    msg_ok "Completed Django migrations and static build"

    msg_info "Starting Services"
    systemctl daemon-reexec
    systemctl start healthchecks
    systemctl start healthchecks-sendalerts
    systemctl reload caddy
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
