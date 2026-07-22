#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: durzo
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/connorgallopo/Tracearr

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Tracearr"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y redis-server
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" NODE_MODULE="corepack" setup_nodejs
  PG_VERSION="18" setup_postgresql

  msg_info "Installing pnpm"
  PNPM_VERSION="$(curl -fsSL "https://raw.githubusercontent.com/connorgallopo/Tracearr/refs/heads/main/package.json" | jq -r '.packageManager | split("@")[1]' | cut -d'+' -f1)"
  COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  export COREPACK_ENABLE_DOWNLOAD_PROMPT
  $STD corepack prepare "pnpm@${PNPM_VERSION}" --activate
  msg_ok "Installed pnpm"

  msg_info "Installing TimescaleDB"
  setup_deb822_repo \
    "timescaledb" \
    "https://packagecloud.io/timescale/timescaledb/gpgkey" \
    "https://packagecloud.io/timescale/timescaledb/debian" \
    "$(get_os_info codename)"
  $STD apt install -y \
    timescaledb-2-postgresql-18 \
    timescaledb-tools \
    timescaledb-toolkit-postgresql-18
  total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  ram_for_tsdb=$((total_ram_kb / 1024 / 2))
  $STD timescaledb-tune -yes -memory "${ram_for_tsdb}MB"
  $STD systemctl restart postgresql
  msg_ok "Installed TimescaleDB"

  PG_DB_NAME="tracearr_db" PG_DB_USER="tracearr" PG_DB_EXTENSIONS="timescaledb,timescaledb_toolkit" PG_DB_GRANT_SUPERUSER="true" setup_postgresql_db

  msg_info "Installing tailscale"
  setup_deb822_repo \
    "tailscale" \
    "https://pkgs.tailscale.com/stable/$(get_os_info id)/$(get_os_info codename).noarmor.gpg" \
    "https://pkgs.tailscale.com/stable/$(get_os_info id)/" \
    "$(get_os_info codename)"
  $STD apt install -y tailscale
  $STD systemctl disable --now tailscaled
  $STD systemctl stop tailscaled
  msg_ok "Installed tailscale"

  RELEASE=$(get_latest_github_release "connorgallopo/Tracearr")
  fetch_and_deploy_gh_release "tracearr" "connorgallopo/Tracearr" "tarball" "latest" "/opt/tracearr.build"

  msg_info "Building Tracearr"
  TZ=$(cat /etc/timezone)
  export TZ
  NODE_OPTIONS="--max-old-space-size=4096"
  export NODE_OPTIONS
  cd /opt/tracearr.build || exit
  $STD pnpm install --frozen-lockfile --force
  $STD pnpm turbo telemetry disable
  $STD pnpm turbo run build --no-daemon --filter=@tracearr/shared --filter=@tracearr/server --filter=@tracearr/web
  mkdir -p /opt/tracearr/{packages/shared,apps/server,apps/web,apps/server/src/db}
  cp -rf package.json /opt/tracearr/
  cp -rf pnpm-workspace.yaml /opt/tracearr/
  cp -rf pnpm-lock.yaml /opt/tracearr/
  cp -rf apps/server/package.json /opt/tracearr/apps/server/
  cp -rf apps/server/dist /opt/tracearr/apps/server/dist
  cp -rf apps/server/scripts /opt/tracearr/apps/server/scripts
  cp -rf apps/web/dist /opt/tracearr/apps/web/dist
  cp -rf packages/shared/package.json /opt/tracearr/packages/shared/
  cp -rf packages/shared/dist /opt/tracearr/packages/shared/dist
  cp -rf apps/server/src/db/migrations /opt/tracearr/apps/server/src/db/migrations
  cp -rf data /opt/tracearr/data
  mkdir -p /opt/tracearr/data/image-cache
  rm -rf /opt/tracearr.build
  cd /opt/tracearr || exit
  $STD pnpm install --prod --frozen-lockfile --ignore-scripts
  msg_ok "Built Tracearr"

  msg_info "Configuring Tracearr"
  $STD useradd -r -s /bin/false -U tracearr
  $STD chown -R tracearr:tracearr /opt/tracearr
  install -d -m 750 -o tracearr -g tracearr /data/tracearr
  install -d -m 750 -o tracearr -g tracearr /data/backup
  JWT_SECRET=$(openssl rand -hex 32)
  export JWT_SECRET
  COOKIE_SECRET=$(openssl rand -hex 32)
  export COOKIE_SECRET
  cat << EOF > /data/tracearr/.env
DATABASE_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}
REDIS_URL=redis://127.0.0.1:6379
PORT=3000
HOST=0.0.0.0
NODE_ENV=production
TZ=${TZ}
LOG_LEVEL=info
JWT_SECRET=${JWT_SECRET}
COOKIE_SECRET=${COOKIE_SECRET}
APP_VERSION=${RELEASE}
#CORS_ORIGIN=http://localhost:5173
EOF
  chmod 600 /data/tracearr/.env
  chown -R tracearr:tracearr /data/tracearr
  msg_ok "Configured Tracearr"

  msg_info "Creating Services"
  cat << EOF > /data/tracearr/prestart.sh
#!/usr/bin/env bash
# =============================================================================
# Tune PostgreSQL for available resources (runs every startup)
# =============================================================================
# timescaledb-tune automatically optimizes PostgreSQL settings based on
# available RAM and CPU. Safe to run repeatedly - recalculates if resources change.
if command -v timescaledb-tune &> /dev/null; then
    total_ram_kb=\$(grep MemTotal /proc/meminfo | awk '{print \$2}')
    ram_for_tsdb=\$((total_ram_kb / 1024 / 2))
    timescaledb-tune -yes -memory "\$ram_for_tsdb"MB --quiet 2>/dev/null \
        || echo "Warning: timescaledb-tune failed (non-fatal)"
fi
# =============================================================================
# Ensure required PostgreSQL settings for Tracearr
# =============================================================================
pg_config_file="/etc/postgresql/18/main/postgresql.conf"
if [ -f \$pg_config_file ]; then
    # Ensure max_tuples_decompressed_per_dml_transaction is set
    if grep -q "^timescaledb\.max_tuples_decompressed_per_dml_transaction" \$pg_config_file; then
        # Setting exists (uncommented) - update if not 0
        current_value=\$(grep "^timescaledb\.max_tuples_decompressed_per_dml_transaction" \$pg_config_file | grep -oE '[0-9]+' | head -1)
        if [ -n "\$current_value" ] && [ "\$current_value" -ne 0 ]; then
            sed -i "s/^timescaledb\.max_tuples_decompressed_per_dml_transaction.*/timescaledb.max_tuples_decompressed_per_dml_transaction = 0/" \$pg_config_file
        fi
    elif ! grep -q "^timescaledb\.max_tuples_decompressed_per_dml_transaction" \$pg_config_file; then
        echo "" >> \$pg_config_file
        echo "# Allow unlimited tuple decompression for migrations on compressed hypertables" >> \$pg_config_file
        echo "timescaledb.max_tuples_decompressed_per_dml_transaction = 0" >> \$pg_config_file
    fi
    # Ensure max_locks_per_transaction is set (for existing databases)
    if grep -q "^max_locks_per_transaction" \$pg_config_file; then
        # Setting exists (uncommented) - update if below 4096
        current_value=\$(grep "^max_locks_per_transaction" \$pg_config_file | grep -oE '[0-9]+' | head -1)
        if [ -n "\$current_value" ] && [ "\$current_value" -lt 4096 ]; then
            sed -i "s/^max_locks_per_transaction.*/max_locks_per_transaction = 4096/" \$pg_config_file
        fi
    elif ! grep -q "^max_locks_per_transaction" \$pg_config_file; then
        echo "" >> \$pg_config_file
        echo "# Increase lock table size for TimescaleDB hypertables with many chunks" >> \$pg_config_file
        echo "max_locks_per_transaction = 4096" >> \$pg_config_file
    fi
fi
systemctl restart postgresql
sudo -u postgres psql -c "ALTER USER tracearr WITH SUPERUSER;"
EOF
  chmod +x /data/tracearr/prestart.sh
  cat << EOF > /lib/systemd/system/tracearr.service
[Unit]
Description=Tracearr Web Server
After=network.target postgresql.service redis-server.service

[Service]
Type=simple
KillMode=control-group
EnvironmentFile=/data/tracearr/.env
WorkingDirectory=/opt/tracearr
ExecStartPre=+/data/tracearr/prestart.sh
ExecStart=node /opt/tracearr/apps/server/dist/index.js
Restart=on-failure
RestartSec=10
User=tracearr

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now postgresql redis-server tracearr
  msg_ok "Created Services"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /lib/systemd/system/tracearr.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="24" setup_nodejs

  msg_info "Updating prestart script"
  cat << EOF > /data/tracearr/prestart.sh
#!/usr/bin/env bash
# =============================================================================
# Tune PostgreSQL for available resources (runs every startup)
# =============================================================================
if command -v timescaledb-tune &> /dev/null; then
    total_ram_kb=\$(grep MemTotal /proc/meminfo | awk '{print \$2}')
    ram_for_tsdb=\$((total_ram_kb / 1024 / 2))
    timescaledb-tune -yes -memory "\$ram_for_tsdb"MB --quiet 2>/dev/null \
        || echo "Warning: timescaledb-tune failed (non-fatal)"
fi
pg_config_file="/etc/postgresql/18/main/postgresql.conf"
if [ -f \$pg_config_file ]; then
    if grep -q "^timescaledb\.max_tuples_decompressed_per_dml_transaction" \$pg_config_file; then
        current_value=\$(grep "^timescaledb\.max_tuples_decompressed_per_dml_transaction" \$pg_config_file | grep -oE '[0-9]+' | head -1)
        if [ -n "\$current_value" ] && [ "\$current_value" -ne 0 ]; then
            sed -i "s/^timescaledb\.max_tuples_decompressed_per_dml_transaction.*/timescaledb.max_tuples_decompressed_per_dml_transaction = 0/" \$pg_config_file
        fi
    elif ! grep -q "^timescaledb\.max_tuples_decompressed_per_dml_transaction" \$pg_config_file; then
        echo "" >> \$pg_config_file
        echo "# Allow unlimited tuple decompression for migrations on compressed hypertables" >> \$pg_config_file
        echo "timescaledb.max_tuples_decompressed_per_dml_transaction = 0" >> \$pg_config_file
    fi
    if grep -q "^max_locks_per_transaction" \$pg_config_file; then
        current_value=\$(grep "^max_locks_per_transaction" \$pg_config_file | grep -oE '[0-9]+' | head -1)
        if [ -n "\$current_value" ] && [ "\$current_value" -lt 4096 ]; then
            sed -i "s/^max_locks_per_transaction.*/max_locks_per_transaction = 4096/" \$pg_config_file
        fi
    elif ! grep -q "^max_locks_per_transaction" \$pg_config_file; then
        echo "" >> \$pg_config_file
        echo "# Increase lock table size for TimescaleDB hypertables with many chunks" >> \$pg_config_file
        echo "max_locks_per_transaction = 4096" >> \$pg_config_file
    fi
fi
systemctl restart postgresql
sudo -u postgres psql -c "ALTER USER tracearr WITH SUPERUSER;"
EOF
  chmod +x /data/tracearr/prestart.sh

  if command -v tailscale > /dev/null 2>&1; then
    $STD systemctl disable --now tailscaled
    $STD systemctl stop tailscaled
    msg_ok "Tailscale already installed"
  else
    msg_info "Installing tailscale"
    setup_deb822_repo \
      "tailscale" \
      "https://pkgs.tailscale.com/stable/$(get_os_info id)/$(get_os_info codename).noarmor.gpg" \
      "https://pkgs.tailscale.com/stable/$(get_os_info id)/" \
      "$(get_os_info codename)"
    $STD apt install -y tailscale
    $STD systemctl disable --now tailscaled
    $STD systemctl stop tailscaled
    msg_ok "Installed tailscale"
  fi

  if check_for_gh_release "tracearr" "connorgallopo/Tracearr"; then
    msg_info "Stopping Services"
    systemctl stop tracearr postgresql redis-server
    msg_ok "Stopped Services"

    msg_info "Updating pnpm"
    PNPM_VERSION="$(curl -fsSL "https://raw.githubusercontent.com/connorgallopo/Tracearr/refs/heads/main/package.json" | jq -r '.packageManager | split("@")[1]' | cut -d'+' -f1)"
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0
    export COREPACK_ENABLE_DOWNLOAD_PROMPT
    $STD corepack prepare "pnpm@${PNPM_VERSION}" --activate
    msg_ok "Updated pnpm"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "tracearr" "connorgallopo/Tracearr" "tarball" "latest" "/opt/tracearr.build"

    msg_info "Building Tracearr"
    TZ=$(cat /etc/timezone)
    export TZ
    NODE_OPTIONS="--max-old-space-size=4096"
    export NODE_OPTIONS
    cd /opt/tracearr.build || exit
    $STD pnpm install --frozen-lockfile --force
    $STD pnpm turbo telemetry disable
    $STD pnpm turbo run build --no-daemon --filter=@tracearr/shared --filter=@tracearr/server --filter=@tracearr/web
    rm -rf /opt/tracearr
    mkdir -p /opt/tracearr/{packages/shared,apps/server,apps/web,apps/server/src/db}
    cp -rf package.json /opt/tracearr/
    cp -rf pnpm-workspace.yaml /opt/tracearr/
    cp -rf pnpm-lock.yaml /opt/tracearr/
    cp -rf apps/server/package.json /opt/tracearr/apps/server/
    cp -rf apps/server/dist /opt/tracearr/apps/server/dist
    cp -rf apps/server/scripts /opt/tracearr/apps/server/scripts
    cp -rf apps/web/dist /opt/tracearr/apps/web/dist
    cp -rf packages/shared/package.json /opt/tracearr/packages/shared/
    cp -rf packages/shared/dist /opt/tracearr/packages/shared/dist
    cp -rf apps/server/src/db/migrations /opt/tracearr/apps/server/src/db/migrations
    cp -rf data /opt/tracearr/data
    mkdir -p /opt/tracearr/data/image-cache
    rm -rf /opt/tracearr.build
    cd /opt/tracearr || exit
    $STD pnpm install --prod --frozen-lockfile --ignore-scripts
    $STD chown -R tracearr:tracearr /opt/tracearr
    msg_ok "Built Tracearr"

    msg_info "Configuring Tracearr"
    sed -i "s|^APP_VERSION=.*|APP_VERSION=${CHECK_UPDATE_RELEASE#v}|" /data/tracearr/.env
    chmod 600 /data/tracearr/.env
    chown -R tracearr:tracearr /data/tracearr
    mkdir -p /data/backup
    chown -R tracearr:tracearr /data/backup
    msg_ok "Configured Tracearr"

    msg_info "Starting services"
    systemctl start postgresql redis-server tracearr
    msg_ok "Started services"
    msg_ok "Updated successfully!"
  else
    msg_info "Restarting service"
    systemctl restart tracearr
    msg_ok "Restarted service"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
