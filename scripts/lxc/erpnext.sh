#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/frappe/erpnext

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="ERPNext"
var_tags="${var_tags:-erp;business;accounting}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    git \
    build-essential \
    python3-dev \
    libffi-dev \
    libssl-dev \
    redis-server \
    nginx \
    supervisor \
    fail2ban \
    xvfb \
    libfontconfig1 \
    libxrender1 \
    fontconfig \
    libjpeg-dev \
    libmariadb-dev \
    python3-pip \
    pkg-config \
    cron
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" NODE_MODULE="yarn" setup_nodejs
  UV_PYTHON="3.14" setup_uv
  setup_mariadb

  msg_info "Configuring MariaDB for ERPNext"
  cat << EOF > /etc/mysql/mariadb.conf.d/50-erpnext.cnf
[mysqld]
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci

[client]
default-character-set=utf8mb4
EOF
  $STD systemctl restart mariadb
  msg_ok "Configured MariaDB for ERPNext"

  msg_info "Installing wkhtmltopdf"
  arch=$(dpkg --print-architecture)
  WKHTMLTOPDF_URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_${arch}.deb"
  $STD curl -fsSL -o /tmp/wkhtmltox.deb "$WKHTMLTOPDF_URL"
  $STD apt install -y /tmp/wkhtmltox.deb
  rm -f /tmp/wkhtmltox.deb
  msg_ok "Installed wkhtmltopdf"

  msg_info "Installing Frappe Bench"
  useradd -m -s /bin/bash frappe
  chown frappe:frappe /opt
  echo "frappe ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/frappe
  $STD sudo -u frappe bash -c 'export PATH="$HOME/.local/bin:$PATH"; uv tool install frappe-bench'
  msg_ok "Installed Frappe Bench"

  msg_info "Initializing Frappe Bench"
  ADMIN_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  DB_ROOT_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}'; FLUSH PRIVILEGES;"
  $STD sudo -u frappe bash -c 'export PATH="$HOME/.local/bin:$PATH"; uv python install 3.14'
  $STD sudo -u frappe bash -c 'export PATH="$HOME/.local/bin:$PATH"; cd /opt && bench init --frappe-branch version-16 --python "$(uv python find 3.14)" frappe-bench'
  $STD sudo -u frappe bash -c 'export PATH="$HOME/.local/bin:$PATH"; cd /opt/frappe-bench && bench get-app erpnext --branch version-16'

  msg_info "Starting Redis Services for Site Setup"
  $STD sudo -u frappe bash -c 'redis-server /opt/frappe-bench/config/redis_queue.conf --daemonize yes'
  $STD sudo -u frappe bash -c 'redis-server /opt/frappe-bench/config/redis_cache.conf --daemonize yes'
  sleep 3
  msg_ok "Started Redis Services for Site Setup"

  $STD sudo -u frappe bash -c "export PATH=\"\$HOME/.local/bin:\$PATH\"; cd /opt/frappe-bench && bench new-site site1.local --db-root-username root --db-root-password \"$DB_ROOT_PASS\" --admin-password \"$ADMIN_PASS\" --install-app erpnext --set-default"
  msg_ok "Initialized Frappe Bench"

  msg_info "Configuring ERPNext"
  cat << EOF > /opt/frappe-bench/.env
ADMIN_PASSWORD=${ADMIN_PASS}
DB_ROOT_PASSWORD=${DB_ROOT_PASS}
SITE_NAME=site1.local
EOF
  cat << EOF > /root/erpnext.creds
ERPNext Credentials
==================
Admin Username: Administrator
Admin Password: ${ADMIN_PASS}
DB Root Password: ${DB_ROOT_PASS}
Site Name: site1.local
EOF
  $STD systemctl enable --now redis-server
  msg_ok "Configured ERPNext"

  msg_info "Setting up Production"
  BENCH_PY="/home/frappe/.local/share/uv/tools/frappe-bench/bin/python"
  $STD sudo -u frappe bash -c "curl -fsSL https://bootstrap.pypa.io/get-pip.py | \"${BENCH_PY}\""
  $STD sudo -u frappe bash -c 'export PATH="$HOME/.local/bin:$PATH"; uv tool install ansible'
  ln -sf /home/frappe/.local/bin/ansible* /usr/local/bin/
  $STD bash -c 'export PATH="/home/frappe/.local/bin:$PATH"; cd /opt/frappe-bench && bench setup production frappe --yes'
  ln -sf /opt/frappe-bench/config/supervisor.conf /etc/supervisor/conf.d/frappe-bench.conf
  $STD supervisorctl reread
  $STD supervisorctl update
  $STD systemctl enable --now supervisor
  msg_ok "Set up Production"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
  echo -e "${INFO}${YW} Credentials:${CL}"
  echo -e "${TAB}${BGN}Username: Administrator${CL}"
  echo -e "${TAB}${BGN}Password: see /root/erpnext.creds${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/frappe-bench ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  FRAPPE_MAJOR="$(grep -oP '__version__\s*=\s*[\x27"]\K[0-9]+' /opt/frappe-bench/apps/frappe/frappe/__init__.py 2> /dev/null || echo 0)"
  SITE="$(ls /opt/frappe-bench/sites/*/site_config.json 2> /dev/null | head -1 | cut -d/ -f5)"
  [[ -z "$SITE" ]] && SITE="site1.local"

  msg_info "Stopping ERPNext service"
  $STD supervisorctl stop all
  msg_ok "Stopped ERPNext service"

  if [[ "${FRAPPE_MAJOR:-0}" -lt 16 ]] && { [[ "${PHS_SILENT:-0}" == "1" ]] || whiptail --backtitle "Proxmox VE Helper Scripts" --title "ERPNext v16 Major Upgrade" \
    --yesno "A major upgrade from Frappe/ERPNext v15 to v16 is available.\n\nUpgrade to v16 now?" 16 78; }; then

    msg_info "Backing up site ${SITE}"
    $STD sudo -u frappe bash -c "export PATH=\"\$HOME/.local/bin:/usr/local/bin:\$PATH\"; cd /opt/frappe-bench && bench --site ${SITE} backup"
    msg_ok "Backup created"

    msg_info "Installing Dependencies"
    $STD apt-get install -y pkg-config
    $STD sudo -u frappe bash -c 'export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"; cd /opt/frappe-bench && uv python install 3.14'
    msg_ok "Installed Dependencies"

    msg_info "Migrating bench environment"
    $STD sudo -u frappe bash -c 'export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"; cd /opt/frappe-bench && bench migrate-env "$(uv python find 3.14)"'
    msg_ok "Migrated environment"

    msg_info "Switching Frappe and ERPNext to v16 (Patience)"
    $STD sudo -u frappe bash -c 'export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"; cd /opt/frappe-bench && bench switch-to-branch version-16 frappe erpnext --upgrade' || true
    NEW_MAJOR="$(grep -oP '__version__\s*=\s*[\x27"]\K[0-9]+' /opt/frappe-bench/apps/frappe/frappe/__init__.py 2> /dev/null || echo 0)"
    if [[ "${NEW_MAJOR:-0}" -lt 16 ]]; then
      msg_error "Failed to switch Frappe/ERPNext to v16"
      exit 250
    fi
    msg_ok "Switched to v16"

    msg_info "Running database migration (Patience)"
    for i in 1 2 3; do
      $STD sudo -u frappe bash -c "export PATH=\"\$HOME/.local/bin:/usr/local/bin:\$PATH\"; cd /opt/frappe-bench && bench --site ${SITE} migrate" && break
      [[ "$i" -eq 3 ]] && {
        msg_error "Database migration failed after 3 attempts"
        exit 253
      }
    done
    msg_ok "Database migrated"

    msg_info "Building assets"
    $STD sudo -u frappe bash -c 'export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"; cd /opt/frappe-bench && bench build --production'
    msg_ok "Assets built"

    msg_info "Restarting ERPNext"
    $STD sudo -u frappe bash -c 'export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"; cd /opt/frappe-bench && bench restart'
    msg_ok "Upgraded ERPNext to v16"
  else
    msg_info "Updating ERPNext"
    $STD sudo -u frappe bash -c 'export PATH="$HOME/.local/bin:$PATH"; cd /opt/frappe-bench && bench update --reset'
    msg_ok "Updated ERPNext"
  fi
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
