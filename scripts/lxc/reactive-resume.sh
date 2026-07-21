#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: vhsdream (vhsdream) | Co-Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://rxresume.org
# shellcheck disable=SC2034
APP="Reactive-Resume"
var_tags="${var_tags:-documents}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="reactive_resume" PG_DB_USER="reactive_resume" setup_postgresql_db
  NODE_VERSION="24" NODE_MODULE="corepack" setup_nodejs

  msg_info "Installing Dependencies"
  $STD apt install -y \
    chromium \
    git
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "reactive-resume" "amruthpillai/reactive-resume" "tarball"

  msg_info "Building Reactive Resume (Patience)"
  cd /opt/reactive-resume || exit
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  corepack prepare --activate
  export NODE_ENV="production"
  export CI="true"
  $STD pnpm install --frozen-lockfile
  $STD pnpm run build
  mkdir -p /opt/reactive-resume/data
  msg_ok "Built Reactive Resume"

  msg_info "Configuring Reactive Resume"
  AUTH_SECRET=$(openssl rand -hex 32)
  cat << EOF > /opt/reactive-resume/.env
# Reactive Resume v5 Configuration
NODE_ENV=production
PORT=3000

# Public URL (change to your FQDN when using a reverse proxy)
APP_URL=http://${IP}:3000

# Database
DATABASE_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}

# Authentication Secret (do not change after initial setup)
AUTH_SECRET=${AUTH_SECRET}

# Printer (headless Chromium for PDF generation)
PRINTER_ENDPOINT=http://127.0.0.1:9222

# Storage: uses local filesystem (/opt/reactive-resume/data) when S3 is not configured
# S3_ACCESS_KEY_ID=
# S3_SECRET_ACCESS_KEY=
# S3_REGION=us-east-1
# S3_ENDPOINT=
# S3_BUCKET=
# S3_FORCE_PATH_STYLE=false

# Email (optional, logs to console if not configured)
# SMTP_HOST=
# SMTP_PORT=465
# SMTP_USER=
# SMTP_PASS=
# SMTP_FROM=Reactive Resume <noreply@localhost>

# OAuth (optional)
# GITHUB_CLIENT_ID=
# GITHUB_CLIENT_SECRET=
# GOOGLE_CLIENT_ID=
# GOOGLE_CLIENT_SECRET=

# Feature Flags
# FLAG_DISABLE_SIGNUPS=false
# FLAG_DISABLE_EMAIL_AUTH=false
EOF
  msg_ok "Configured Reactive Resume"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/chromium-printer.service
[Unit]
Description=Headless Chromium for Reactive Resume PDF generation
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/chromium --headless --disable-gpu --no-sandbox --no-zygote --disable-dev-shm-usage --remote-debugging-address=127.0.0.1 --remote-debugging-port=9222
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/reactive-resume.service
[Unit]
Description=Reactive Resume
After=network.target postgresql.service chromium-printer.service
Wants=postgresql.service chromium-printer.service

[Service]
WorkingDirectory=/opt/reactive-resume/apps/server
EnvironmentFile=/opt/reactive-resume/.env
ExecStart=/usr/bin/node dist/index.mjs
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable -q --now chromium-printer.service reactive-resume.service
  msg_ok "Created Services"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/reactive-resume.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "reactive-resume" "amruthpillai/reactive-resume"; then
    msg_info "Stopping services"
    systemctl stop reactive-resume
    msg_ok "Stopped services"

    cp /opt/reactive-resume/.env /opt/reactive-resume.env.bak
    NODE_VERSION="24" NODE_MODULE="corepack" setup_nodejs
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "reactive-resume" "amruthpillai/reactive-resume" "tarball" "latest" "/opt/reactive-resume"

    msg_info "Updating Reactive Resume (Patience)"
    cd /opt/reactive-resume || exit
    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
    corepack prepare --activate
    export CI="true"
    export NODE_ENV="production"
    $STD pnpm install --frozen-lockfile
    $STD pnpm run build
    mv /opt/reactive-resume.env.bak /opt/reactive-resume/.env
    msg_ok "Updated Reactive Resume"

    msg_info "Updating Service"
    sed -i 's|WorkingDirectory=/opt/reactive-resume/apps/web|WorkingDirectory=/opt/reactive-resume/apps/server|; s|ExecStart=/usr/bin/node .output/server/index.mjs|ExecStart=/usr/bin/node dist/index.mjs|' /etc/systemd/system/reactive-resume.service
    systemctl daemon-reload
    msg_ok "Updated Service"

    msg_info "Restarting services"
    systemctl start chromium-printer reactive-resume
    msg_ok "Restarted services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
