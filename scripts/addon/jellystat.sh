#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/CyferShepard/Jellystat

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Jellystat"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_install_path="${var_addon_install_path:-/opt/jellystat}"
var_addon_config_path="${var_addon_config_path:-/opt/jellystat/.env}"
var_addon_service_path="${var_addon_service_path:-/etc/systemd/system/jellystat.service}"
var_addon_backup_dir="${var_addon_backup_dir:-/opt/jellystat_backup}"
var_addon_creds_path="${var_addon_creds_path:-/root/jellystat.creds}"
var_addon_db_name="${var_addon_db_name:-jellystat}"
var_addon_db_user="${var_addon_db_user:-jellystat}"
var_addon_default_port="${var_addon_default_port:-3000}"

function header_info() {
  clear
  cat << "EOF"
       __     ____           __        __
      / /__  / / /_  _______/ /_____ _/ /_
 __  / / _ \/ / / / / / ___/ __/ __ `/ __/
/ /_/ /  __/ / / /_/ (__  ) /_/ /_/ / /_
\____/\___/_/_/\__, /____/\__/\__,_/\__/
              /____/
EOF
}

function install_script() {
  if [[ "$OS_FAMILY" != "debian" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu only)"
    exit 1
  fi

  if command -v node &> /dev/null; then
    msg_ok "Node.js already installed ($(node -v))"
  else
    NODE_VERSION="22" setup_nodejs
  fi

  if command -v psql &> /dev/null; then
    msg_ok "PostgreSQL already installed"
  else
    PG_VERSION="17" setup_postgresql
  fi

  local DB_PASS

  msg_info "Setting up PostgreSQL database"

  if sudo -u postgres psql -lqt 2> /dev/null | cut -d \| -f 1 | grep -qw "$var_addon_db_name"; then
    msg_warn "Database '${var_addon_db_name}' already exists - skipping creation"
    echo -n "${TAB}Enter existing database password for '${var_addon_db_user}': "
    read -rs DB_PASS || true
    echo ""
  else
    DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c16)

    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${var_addon_db_user}'" 2> /dev/null | grep -q 1; then
      msg_info "User '${var_addon_db_user}' exists, updating password"
      $STD sudo -u postgres psql -c "ALTER USER ${var_addon_db_user} WITH PASSWORD '${DB_PASS}';" || {
        msg_error "Failed to update PostgreSQL user"
        return 1
      }
    else
      $STD sudo -u postgres psql -c "CREATE USER ${var_addon_db_user} WITH PASSWORD '${DB_PASS}';" || {
        msg_error "Failed to create PostgreSQL user"
        return 1
      }
    fi

    $STD sudo -u postgres psql -c "CREATE DATABASE ${var_addon_db_name} WITH OWNER ${var_addon_db_user} ENCODING 'UTF8' LC_COLLATE='C' LC_CTYPE='C' TEMPLATE template0;" || {
      msg_error "Failed to create PostgreSQL database"
      return 1
    }
    $STD sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${var_addon_db_name} TO ${var_addon_db_user};" || {
      msg_error "Failed to grant privileges"
      return 1
    }

    $STD sudo -u postgres psql -d "${var_addon_db_name}" -c "GRANT ALL ON SCHEMA public TO ${var_addon_db_user};" || true

    local PG_HBA
    PG_HBA=$(sudo -u postgres psql -tAc "SHOW hba_file;" 2> /dev/null | tr -d ' ')
    if [[ -n "$PG_HBA" && -f "$PG_HBA" ]]; then
      if ! grep -qE "^host\s+${var_addon_db_name}\s+${var_addon_db_user}\s+127.0.0.1" "$PG_HBA"; then
        msg_info "Configuring PostgreSQL authentication"
        sed -i "/^# IPv4 local connections:/a host    ${var_addon_db_name}    ${var_addon_db_user}    127.0.0.1/32    scram-sha-256" "$PG_HBA"
        sed -i "/^# IPv4 local connections:/a host    ${var_addon_db_name}    ${var_addon_db_user}    ::1/128         scram-sha-256" "$PG_HBA"
        systemctl reload postgresql
        msg_ok "Configured PostgreSQL authentication"
      fi
    fi

    msg_ok "Created PostgreSQL database '${var_addon_db_name}'"
  fi

  local JWT_SECRET
  JWT_SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c32)

  rm -f "$HOME/.jellystat"
  fetch_and_deploy_gh_release "jellystat" "CyferShepard/Jellystat" "tarball" "latest" "$var_addon_install_path"

  msg_info "Installing dependencies"
  cd "$var_addon_install_path" || exit
  $STD npm install
  msg_ok "Installed dependencies"

  msg_info "Building ${APP}"
  $STD npm run build
  msg_ok "Built ${APP}"

  msg_info "Creating configuration"
  cat << EOF > "$var_addon_config_path"
# Jellystat Configuration
# Database
POSTGRES_USER=${var_addon_db_user}
POSTGRES_PASSWORD=${DB_PASS}
POSTGRES_IP=localhost
POSTGRES_PORT=5432
POSTGRES_DB=${var_addon_db_name}

# Security
JWT_SECRET=${JWT_SECRET}

# Server
JS_LISTEN_IP=0.0.0.0
JS_BASE_URL=/
TZ=$(cat /etc/timezone 2> /dev/null || echo "UTC")

# Optional: GeoLite for IP Geolocation
# JS_GEOLITE_ACCOUNT_ID=
# JS_GEOLITE_LICENSE_KEY=

# Optional: Master Override (if you forget your password)
# JS_USER=admin
# JS_PASSWORD=admin

# Optional: Minimum playback duration to record (seconds)
# MINIMUM_SECONDS_TO_INCLUDE_PLAYBACK=1

# Optional: Self-signed certificates
REJECT_SELF_SIGNED_CERTIFICATES=true
EOF
  chmod 600 "$var_addon_config_path"
  msg_ok "Created configuration"

  msg_info "Creating service"
  cat << EOF > "$var_addon_service_path"
[Unit]
Description=Jellystat - Statistics for Jellyfin
After=network.target postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=${var_addon_install_path}/backend
EnvironmentFile=${var_addon_config_path}
ExecStart=/usr/bin/node ${var_addon_install_path}/backend/server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now jellystat
  msg_ok "Created and started service"

  msg_info "Saving credentials"
  cat << EOF > "$var_addon_creds_path"
Jellystat Credentials
=====================
Database User: ${var_addon_db_user}
Database Password: ${DB_PASS}
Database Name: ${var_addon_db_name}
JWT Secret: ${JWT_SECRET}

Web UI: http://${LOCAL_IP}:${var_addon_default_port}
EOF
  chmod 600 "$var_addon_creds_path"
  msg_ok "Saved credentials to ${var_addon_creds_path}"
}

function post_install_script() {
  echo ""
  msg_ok "${APP} is reachable at: ${BL}http://${LOCAL_IP}:${var_addon_default_port}${CL}"
  msg_ok "Credentials saved to: ${BL}${var_addon_creds_path}${CL}"
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
  echo ""
  msg_warn "On first access, you'll need to configure your Jellyfin server connection."
}

function update_script() {
  if check_for_gh_release "jellystat" "CyferShepard/Jellystat"; then
    msg_info "Stopping service"
    systemctl stop jellystat.service &> /dev/null || true
    msg_ok "Stopped service"

    BACKUP_DIR="$var_addon_backup_dir" create_backup "$var_addon_config_path"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "jellystat" "CyferShepard/Jellystat" "tarball" "latest" "$var_addon_install_path"

    BACKUP_DIR="$var_addon_backup_dir" restore_backup

    msg_info "Installing dependencies"
    cd "$var_addon_install_path" || exit
    $STD npm install
    msg_ok "Installed dependencies"

    msg_info "Building ${APP}"
    $STD npm run build
    msg_ok "Built ${APP}"

    msg_info "Starting service"
    systemctl start jellystat
    msg_ok "Started service"
    msg_ok "Updated successfully"
  fi
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"
  systemctl disable --now jellystat.service &> /dev/null || true
  rm -f "$var_addon_service_path"
  rm -rf "$var_addon_install_path"
  rm -f "$HOME/.jellystat"
  msg_ok "${APP} has been uninstalled"

  echo ""
  echo -n "${TAB}Also remove PostgreSQL database '${var_addon_db_name}'? (y/N): "
  read -r db_prompt || true
  if [[ "${db_prompt,,}" =~ ^(y|yes)$ ]]; then
    if command -v psql &> /dev/null; then
      msg_info "Removing PostgreSQL database and user"
      $STD sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${var_addon_db_name};" &> /dev/null || true
      $STD sudo -u postgres psql -c "DROP USER IF EXISTS ${var_addon_db_user};" &> /dev/null || true
      msg_ok "Removed PostgreSQL database '${var_addon_db_name}' and user '${var_addon_db_user}'"
    else
      msg_warn "PostgreSQL not found - database may have been removed already"
    fi
  else
    msg_warn "PostgreSQL database was NOT removed. Remove manually if needed:"
    echo -e "${TAB}  sudo -u postgres psql -c \"DROP DATABASE ${var_addon_db_name};\""
    echo -e "${TAB}  sudo -u postgres psql -c \"DROP USER ${var_addon_db_user};\""
  fi
}

# Addons run inside arbitrary containers that may lack curl — ensure the
# transport before sourcing the framework (everything else is bootstrapped
# by install.func from this point on)
if ! command -v curl > /dev/null 2>&1; then
  if [[ -f /etc/alpine-release ]]; then
    apk update &> /dev/null && apk add --no-cache curl &> /dev/null
  else
    apt-get update &> /dev/null && apt-get install -y curl &> /dev/null
  fi
fi
command -v curl > /dev/null 2>&1 || {
  echo "FATAL: curl is required and could not be installed" >&2
  exit 1
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon_lxc")
