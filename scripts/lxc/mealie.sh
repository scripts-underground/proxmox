#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://mealie.io | Github: https://github.com/mealie-recipes/mealie

# shellcheck disable=SC2034
APP="Mealie"
var_tags="${var_tags:-recipes}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-3072}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    libpq-dev \
    libwebp-dev \
    libsasl2-dev \
    libldap2-dev \
    libldap-common \
    libssl-dev \
    libldap2 \
    gosu \
    iproute2
  msg_ok "Installed Dependencies"

  PYTHON_VERSION="3.12" setup_uv
  PG_VERSION="16" setup_postgresql
  NODE_MODULE="yarn" NODE_VERSION="24" setup_nodejs
  fetch_and_deploy_gh_release "mealie" "mealie-recipes/mealie" "tarball"
  PG_DB_NAME="mealie_db" PG_DB_USER="mealie_user" PG_DB_GRANT_SUPERUSER="true" setup_postgresql_db

  msg_info "Installing Python Dependencies with uv"
  cd /opt/mealie || exit
  $STD uv sync --frozen --extra pgsql
  msg_ok "Installed Python Dependencies"

  msg_info "Building Frontend"
  MEALIE_VERSION=$(< $HOME/.mealie)
  export NUXT_TELEMETRY_DISABLED=1
  cd /opt/mealie/frontend || exit
  SITE_SETTINGS=$(find /opt/mealie/frontend -name "site-settings.vue" -path "*/admin/*" | head -1)
  $STD sed -i "s|https://github.com/mealie-recipes/mealie/commit/|https://github.com/mealie-recipes/mealie/releases/tag/|g" "$SITE_SETTINGS"
  $STD sed -i "s|value: data.buildId,|value: \"v${MEALIE_VERSION}\",|g" "$SITE_SETTINGS"
  $STD sed -i "s|value: data.production ? i18n.t(\"about.production\") : i18n.t(\"about.development\"),|value: \"bare-metal\",|g" "$SITE_SETTINGS"
  $STD yarn install --prefer-offline --frozen-lockfile --non-interactive --production=false --network-timeout 1000000
  $STD yarn generate
  msg_ok "Built Frontend"

  msg_info "Copying Built Frontend"
  mkdir -p /opt/mealie/mealie/frontend
  cp -r /opt/mealie/frontend/dist/* /opt/mealie/mealie/frontend/
  msg_ok "Copied Frontend"

  setup_nltk "averaged_perceptron_tagger_eng" "/nltk_data"

  msg_info "Writing Environment File"
  SECRET=$(openssl rand -hex 32)
  mkdir -p /run/secrets
  CONTAINER_IP=$(get_current_ip)
  cat << EOF > /opt/mealie/mealie.env
MEALIE_HOME=/opt/mealie
NLTK_DATA=/nltk_data
SECRET=${SECRET}

DB_ENGINE=postgres
POSTGRES_SERVER=localhost
POSTGRES_PORT=5432
POSTGRES_USER=${PG_DB_USER}
POSTGRES_PASSWORD=${PG_DB_PASS}
POSTGRES_DB=${PG_DB_NAME}

PRODUCTION=true
HOST=0.0.0.0
PORT=9000
BASE_URL=http://${CONTAINER_IP}:9000
EOF
  msg_ok "Wrote Environment File"

  msg_info "Creating Start Script"
  cat << 'EOF' > /opt/mealie/start.sh
#!/bin/bash
set -a
source /opt/mealie/mealie.env
set +a
exec uv run mealie
EOF
  chmod +x /opt/mealie/start.sh
  msg_ok "Created Start Script"

  msg_info "Creating Systemd Service"
  cat << 'EOF' > /etc/systemd/system/mealie.service
[Unit]
Description=Mealie Recipe Manager
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/mealie
ExecStart=/opt/mealie/start.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now mealie
  msg_ok "Created and Started Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:9000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/mealie ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "mealie" "mealie-recipes/mealie"; then
    PYTHON_VERSION="3.12" setup_uv
    NODE_MODULE="yarn" NODE_VERSION="24" setup_nodejs

    msg_info "Stopping Service"
    systemctl stop mealie
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration"
    cp -f /opt/mealie/mealie.env /opt/mealie.env
    [[ -f /opt/mealie/start.sh ]] && cp -f /opt/mealie/start.sh /opt/mealie.start.sh
    msg_ok "Backup completed"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "mealie" "mealie-recipes/mealie" "tarball"

    msg_info "Restoring Configuration"
    mv -f /opt/mealie.env /opt/mealie/mealie.env
    if [[ -f /opt/mealie.start.sh ]]; then
      mv -f /opt/mealie.start.sh /opt/mealie/start.sh
    else
      cat << 'STARTEOF' > /opt/mealie/start.sh
#!/bin/bash
set -a
source /opt/mealie/mealie.env
set +a
exec uv run mealie
STARTEOF
    fi
    chmod +x /opt/mealie/start.sh
    msg_ok "Configuration restored"

    msg_info "Installing Python Dependencies with uv"
    cd /opt/mealie || exit
    $STD uv sync --frozen --extra pgsql
    msg_ok "Installed Python Dependencies"

    msg_info "Building Frontend"
    MEALIE_VERSION=$(< $HOME/.mealie)
    SITE_SETTINGS=$(find /opt/mealie/frontend -name "site-settings.vue" -path "*/admin/*" | head -1)
    $STD sed -i "s|https://github.com/mealie-recipes/mealie/commit/|https://github.com/mealie-recipes/mealie/releases/tag/|g" "$SITE_SETTINGS"
    $STD sed -i "s|value: data.buildId,|value: \"v${MEALIE_VERSION}\",|g" "$SITE_SETTINGS"
    $STD sed -i "s|value: data.production ? i18n.t(\"about.production\") : i18n.t(\"about.development\"),|value: \"bare-metal\",|g" "$SITE_SETTINGS"
    export NUXT_TELEMETRY_DISABLED=1
    cd /opt/mealie/frontend || exit
    $STD yarn install --prefer-offline --frozen-lockfile --non-interactive --production=false --network-timeout 1000000
    $STD yarn generate
    msg_ok "Built Frontend"

    msg_info "Copying Built Frontend"
    mkdir -p /opt/mealie/mealie/frontend
    cp -r /opt/mealie/frontend/dist/* /opt/mealie/mealie/frontend/
    msg_ok "Copied Frontend"

    setup_nltk "averaged_perceptron_tagger_eng" "/nltk_data"

    msg_info "Starting Service"
    systemctl start mealie
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
