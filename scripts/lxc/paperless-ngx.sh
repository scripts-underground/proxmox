#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://docs.paperless-ngx.com/ | Github: https://github.com/paperless-ngx/paperless-ngx

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Paperless-ngx"
var_tags="${var_tags:-document;management}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-3072}"
var_disk="${var_disk:-12}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies (Patience)"
  $STD apt install -y \
    redis \
    build-essential \
    imagemagick \
    fonts-liberation \
    optipng \
    libpq-dev \
    libmagic-dev \
    libzbar0t64 \
    poppler-utils \
    default-libmysqlclient-dev \
    automake \
    libtool \
    pkg-config \
    libtiff-dev \
    libpng-dev \
    libleptonica-dev \
    unpaper \
    icc-profiles-free \
    qpdf \
    libleptonica6 \
    libxml2 \
    pngquant \
    zlib1g \
    tesseract-ocr \
    tesseract-ocr-eng \
    ghostscript
  msg_ok "Installed Dependencies"

  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="paperlessdb" PG_DB_USER="paperless" setup_postgresql_db
  PYTHON_VERSION="3.13" setup_uv
  fetch_and_deploy_gh_release "paperless" "paperless-ngx/paperless-ngx" "prebuild" "v2.20.15" "/opt/paperless" "paperless*tar.xz"

  msg_info "Setup Paperless-ngx"
  cd /opt/paperless || exit
  rm -rf /opt/paperless/docker
  $STD uv sync --all-extras
  curl -fsSL "https://raw.githubusercontent.com/paperless-ngx/paperless-ngx/main/paperless.conf.example" -o /opt/paperless/paperless.conf
  mkdir -p /opt/paperless_data/{consume,data,media,trash}
  mkdir -p /opt/paperless/static
  SECRET_KEY="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)"
  cat << EOF > ~/paperless-ngx.creds

Paperless-ngx Secret Key: $SECRET_KEY
Paperless-ngx WebUI User: admin
Paperless-ngx WebUI Password: $PG_DB_PASS
EOF
  sed -i \
    -e 's|#PAPERLESS_REDIS=redis://localhost:6379|PAPERLESS_REDIS=redis://localhost:6379|' \
    -e "s|#PAPERLESS_CONSUMPTION_DIR=../consume|PAPERLESS_CONSUMPTION_DIR=/opt/paperless_data/consume|" \
    -e "s|#PAPERLESS_DATA_DIR=../data|PAPERLESS_DATA_DIR=/opt/paperless_data/data|" \
    -e "s|#PAPERLESS_MEDIA_ROOT=../media|PAPERLESS_MEDIA_ROOT=/opt/paperless_data/media|" \
    -e "s|#PAPERLESS_EMPTY_TRASH_DIR=|PAPERLESS_EMPTY_TRASH_DIR=/opt/paperless_data/trash|" \
    -e "s|#PAPERLESS_STATICDIR=../static|PAPERLESS_STATICDIR=/opt/paperless/static|" \
    -e 's|#PAPERLESS_DBHOST=localhost|PAPERLESS_DBHOST=localhost|' \
    -e 's|#PAPERLESS_DBPORT=5432|PAPERLESS_DBPORT=5432|' \
    -e "s|#PAPERLESS_DBNAME=paperless|PAPERLESS_DBNAME=$PG_DB_NAME|" \
    -e "s|#PAPERLESS_DBUSER=paperless|PAPERLESS_DBUSER=$PG_DB_USER|" \
    -e "s|#PAPERLESS_DBPASS=paperless|PAPERLESS_DBPASS=$PG_DB_PASS|" \
    -e "s|#PAPERLESS_SECRET_KEY=change-me|PAPERLESS_SECRET_KEY=$SECRET_KEY|" \
    /opt/paperless/paperless.conf
  cd /opt/paperless/src || exit
  set -a
  . /opt/paperless/paperless.conf
  set +a
  $STD uv run -- python manage.py migrate
  msg_ok "Setup Paperless-ngx"

  msg_info "Setting up admin Paperless-ngx User & Password"
  $STD uv run -- python /opt/paperless/src/manage.py shell << EOF
from django.contrib.auth import get_user_model
UserModel = get_user_model()
user = UserModel.objects.create_user('admin', password='$PG_DB_PASS')
user.is_superuser = True
user.is_staff = True
user.save()
EOF
  msg_ok "Set up admin Paperless-ngx User & Password"

  setup_nltk "snowball_data stopwords punkt_tab" "/usr/share/nltk_data"
  for policy_file in /etc/ImageMagick-6/policy.xml /etc/ImageMagick-7/policy.xml; do
    if [[ -f "$policy_file" ]]; then
      sed -i -e 's/rights="none" pattern="PDF"/rights="read|write" pattern="PDF"/' "$policy_file"
    fi
  done

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/paperless-scheduler.service
[Unit]
Description=Paperless Celery beat
Requires=redis.service

[Service]
WorkingDirectory=/opt/paperless/src
ExecStart=uv run -- celery --app paperless beat --loglevel INFO

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/paperless-task-queue.service
[Unit]
Description=Paperless Celery Workers
Requires=redis.service
After=postgresql.service

[Service]
WorkingDirectory=/opt/paperless/src
ExecStart=uv run -- celery --app paperless worker --loglevel INFO

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/paperless-consumer.service
[Unit]
Description=Paperless consumer
Requires=redis.service

[Service]
WorkingDirectory=/opt/paperless/src
ExecStartPre=/bin/sleep 2
ExecStart=uv run -- python manage.py document_consumer

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/paperless-webserver.service
[Unit]
Description=Paperless webserver
After=network.target
Wants=network.target
Requires=redis.service

[Service]
WorkingDirectory=/opt/paperless/src
ExecStart=uv run -- granian --interface asgi --ws "paperless.asgi:application"
Environment=GRANIAN_HOST=::
Environment=GRANIAN_PORT=8000
Environment=GRANIAN_WORKERS=1

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now paperless-webserver paperless-scheduler paperless-task-queue paperless-consumer
  msg_ok "Created Services"

  read -r -p "${TAB3}Would you like to add Adminer? <y/N> " prompt
  if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
    setup_adminer
  fi
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
  echo -e "${INFO}${YW}Run 'cat paperless-ngx.creds' inside the container for login details.${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/paperless ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE="v2.20.15"
  if check_for_gh_release "paperless" "paperless-ngx/paperless-ngx" "${RELEASE}" "v3 needs further testing"; then
    msg_info "Stopping all Paperless-ngx Services"
    systemctl stop paperless-consumer paperless-webserver paperless-scheduler paperless-task-queue
    msg_ok "Stopped all Paperless-ngx Services"

    if grep -q "uv run" /etc/systemd/system/paperless-webserver.service; then

      msg_info "Backing up configuration"
      local BACKUP_DIR="/opt/paperless_backup_$$"
      mkdir -p "$BACKUP_DIR"
      [[ -f /opt/paperless/paperless.conf ]] && cp /opt/paperless/paperless.conf "$BACKUP_DIR/"
      msg_ok "Backup completed to $BACKUP_DIR"

      PYTHON_VERSION="3.13" setup_uv
      CLEAN_INSTALL=1 fetch_and_deploy_gh_release "paperless" "paperless-ngx/paperless-ngx" "prebuild" "${RELEASE}" "/opt/paperless" "paperless*tar.xz"
      CLEAN_INSTALL=1 fetch_and_deploy_gh_release "jbig2enc" "ie13/jbig2enc" "tarball" "latest" "/opt/jbig2enc"

      . /etc/os-release
      if [ "$VERSION_CODENAME" = "bookworm" ]; then
        setup_gs
      else
        ensure_dependencies ghostscript
      fi

      msg_info "Updating Paperless-ngx"
      cp -r "$BACKUP_DIR"/* /opt/paperless/
      cd /opt/paperless || exit
      $STD uv sync --all-extras
      cd /opt/paperless/src || exit
      $STD uv run -- python manage.py migrate
      msg_ok "Updated Paperless-ngx"

      rm -rf "$BACKUP_DIR"

    else
      msg_warn "You are about to migrate your Paperless-ngx installation to uv!"
      msg_custom "🔒" "It is strongly recommended to take a Proxmox snapshot first:"
      echo -e "   1. Stop the container:  pct stop <CTID>"
      echo -e "   2. Create a snapshot:  pct snapshot <CTID> pre-paperless-uv-migration"
      echo -e "   3. Start the container again\n"

      read -rp "Have you created a snapshot? [y/N]: " confirm
      if [[ ! "$confirm" =~ ^([yY]|[yY][eE][sS])$ ]]; then
        msg_error "Migration aborted. Please create a snapshot first."
        exit
      fi
      msg_info "Migrating old Paperless-ngx installation to uv"
      rm -rf /opt/paperless/venv
      find /opt/paperless -name "__pycache__" -type d -exec rm -rf {} +

      msg_info "Backing up configuration"
      local BACKUP_DIR="/opt/paperless_backup_$$"
      mkdir -p "$BACKUP_DIR"
      [[ -f /opt/paperless/paperless.conf ]] && cp /opt/paperless/paperless.conf "$BACKUP_DIR/"
      msg_ok "Backup completed to $BACKUP_DIR"

      declare -A PATCHES=(
        ["paperless-consumer.service"]="ExecStart=uv run -- python manage.py document_consumer"
        ["paperless-scheduler.service"]="ExecStart=uv run -- celery --app paperless beat --loglevel INFO"
        ["paperless-task-queue.service"]="ExecStart=uv run -- celery --app paperless worker --loglevel INFO"
        ["paperless-webserver.service"]="ExecStart=uv run -- granian --interface asgi --ws \"paperless.asgi:application\""
      )

      for svc in "${!PATCHES[@]}"; do
        path=$(systemctl show -p FragmentPath "$svc" | cut -d= -f2)
        if [[ -n "$path" && -f "$path" ]]; then
          sed -i "s|^ExecStart=.*|${PATCHES[$svc]}|" "$path"
          if [[ "$svc" == "paperless-webserver.service" ]]; then
            grep -q "^Environment=GRANIAN_HOST=" "$path" ||
              sed -i '/^\[Service\]/a Environment=GRANIAN_HOST=::' "$path"
            grep -q "^Environment=GRANIAN_PORT=" "$path" ||
              sed -i '/^\[Service\]/a Environment=GRANIAN_PORT=8000' "$path"
            grep -q "^Environment=GRANIAN_WORKERS=" "$path" ||
              sed -i '/^\[Service\]/a Environment=GRANIAN_WORKERS=1' "$path"
          fi
          msg_ok "Patched $svc"
        else
          msg_error "Service file for $svc not found!"
        fi
      done

      $STD systemctl daemon-reload
      msg_info "Backing up configuration"
      BACKUP_DIR="/opt/paperless_backup_$$"
      mkdir -p "$BACKUP_DIR"
      [[ -f /opt/paperless/paperless.conf ]] && cp /opt/paperless/paperless.conf "$BACKUP_DIR/"
      msg_ok "Backup completed to $BACKUP_DIR"

      PYTHON_VERSION="3.13" setup_uv
      CLEAN_INSTALL=1 fetch_and_deploy_gh_release "paperless" "paperless-ngx/paperless-ngx" "prebuild" "${RELEASE}" "/opt/paperless" "paperless*tar.xz"
      CLEAN_INSTALL=1 fetch_and_deploy_gh_release "jbig2enc" "ie13/jbig2enc" "tarball" "latest" "/opt/jbig2enc"

      . /etc/os-release
      if [ "$VERSION_CODENAME" = "bookworm" ]; then
        setup_gs
      else
        msg_info "Installing Ghostscript"
        ensure_dependencies ghostscript
        msg_ok "Installed Ghostscript"
      fi

      msg_info "Updating Paperless-ngx"
      cp -r "$BACKUP_DIR"/* /opt/paperless/
      cd /opt/paperless || exit
      $STD uv sync --all-extras
      cd /opt/paperless/src || exit
      $STD uv run -- python manage.py migrate
      msg_ok "Paperless-ngx migration and update completed"

      rm -rf "$BACKUP_DIR"
      if [[ -d /opt/paperless/backup ]]; then
        rm -rf /opt/paperless/backup
        msg_ok "Removed old backup directory"
      fi
    fi

    setup_nltk "snowball_data stopwords punkt_tab" "/usr/share/nltk_data"

    msg_info "Starting all Paperless-ngx Services"
    systemctl start paperless-consumer paperless-webserver paperless-scheduler paperless-task-queue
    sleep 1
    msg_ok "Started all Paperless-ngx Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
