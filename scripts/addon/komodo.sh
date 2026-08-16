#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://komo.do/ | Github: https://github.com/moghtech/komodo

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Komodo"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_install_path="${var_addon_install_path:-/opt/komodo}"
var_addon_compose_env="${var_addon_compose_env:-${var_addon_install_path:-/opt/komodo}/compose.env}"
var_addon_compose_base_url="${var_addon_compose_base_url:-https://raw.githubusercontent.com/moghtech/komodo/main/compose}"
var_addon_default_port="${var_addon_default_port:-9120}"

function install_script() {
  if [[ "$OS_FAMILY" != "debian" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu only)"
    exit 1
  fi

  if ! command -v docker > /dev/null 2>&1; then
    msg_info "Installing Docker"
    DOCKER_SKIP_UPDATES=true setup_docker
    msg_ok "Installed Docker"
  fi
  if ! docker compose version > /dev/null 2>&1; then
    msg_error "Docker Compose plugin is not available. Please install it before running this script. Exiting."
    exit 1
  fi
  msg_ok "Docker $(docker --version | cut -d' ' -f3 | tr -d ',') and Docker Compose are available"

  if ! command -v openssl > /dev/null 2>&1; then
    msg_info "Installing openssl"
    $STD apt update
    $STD apt install -y openssl
    msg_ok "Installed openssl"
  fi

  echo -e "${TAB}Choose the database for ${APP}:"
  echo -e "${TAB}  1) MongoDB (recommended)"
  echo -e "${TAB}  2) FerretDB"
  read -erp "${TAB}Enter your choice (default: 1): " DB_CHOICE || true
  DB_CHOICE=${DB_CHOICE:-1}

  case $DB_CHOICE in
    1) DB_COMPOSE_FILE="mongo.compose.yaml" ;;
    2) DB_COMPOSE_FILE="ferretdb.compose.yaml" ;;
    *)
      msg_warn "Invalid choice. Defaulting to MongoDB."
      DB_COMPOSE_FILE="mongo.compose.yaml"
      ;;
  esac

  msg_info "Creating install directory"
  mkdir -p "$var_addon_install_path"
  msg_ok "Created ${var_addon_install_path}"

  msg_info "Downloading Docker Compose file"
  curl -fsSL "${var_addon_compose_base_url}/${DB_COMPOSE_FILE}" -o "${var_addon_install_path}/${DB_COMPOSE_FILE}"
  msg_ok "Downloaded ${DB_COMPOSE_FILE}"

  msg_info "Configuring environment"
  curl -fsSL "${var_addon_compose_base_url}/compose.env" -o "$var_addon_compose_env"

  local db_password webhook_secret jwt_secret
  db_password=$(openssl rand -base64 16 | tr -d '/+=')
  KOMODO_ADMIN_PASSWORD=$(openssl rand -base64 8 | tr -d '/+=')
  webhook_secret=$(openssl rand -base64 24 | tr -d '/+=')
  jwt_secret=$(openssl rand -base64 24 | tr -d '/+=')

  sed -i "s/^KOMODO_DATABASE_USERNAME=.*/KOMODO_DATABASE_USERNAME=komodo_admin/" "$var_addon_compose_env"
  sed -i "s/^KOMODO_DATABASE_PASSWORD=.*/KOMODO_DATABASE_PASSWORD=${db_password}/" "$var_addon_compose_env"
  sed -i "s/^KOMODO_INIT_ADMIN_PASSWORD=changeme/KOMODO_INIT_ADMIN_PASSWORD=${KOMODO_ADMIN_PASSWORD}/" "$var_addon_compose_env"
  sed -i "s/^KOMODO_WEBHOOK_SECRET=.*/KOMODO_WEBHOOK_SECRET=${webhook_secret}/" "$var_addon_compose_env"
  sed -i "s/^KOMODO_JWT_SECRET=.*/KOMODO_JWT_SECRET=${jwt_secret}/" "$var_addon_compose_env"
  msg_ok "Configured environment"

  msg_info "Starting ${APP}"
  (cd "$var_addon_install_path" && $STD docker compose -p komodo -f "${var_addon_install_path}/${DB_COMPOSE_FILE}" --env-file "$var_addon_compose_env" up -d)
  msg_ok "Started ${APP}"

  {
    echo "${APP} Credentials"
    echo ""
    echo "Admin User    : admin"
    echo "Admin Password: ${KOMODO_ADMIN_PASSWORD}"
  } >> ~/komodo.creds
}

function post_install_script() {
  echo ""
  msg_ok "${APP} installed successfully"
  echo -e "${INFO}${YW}Web UI:${CL} ${BGN}http://${LOCAL_IP}:${var_addon_default_port}${CL}"
  echo -e "${INFO}${YW}Login:${CL} ${GN}admin${CL} / ${GN}${KOMODO_ADMIN_PASSWORD}${CL}"
  echo -e "${INFO}${YW}Credentials:${CL} saved to ~/komodo.creds"
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
}

function update_script() {
  if [[ ! -d "$var_addon_install_path" ]]; then
    msg_error "${APP} is not installed. Nothing to update."
    exit 233
  fi

  # find_compose_file (inlined — bundles contain only the hook body)
  local compose_file compose_basename
  compose_file=$(find "$var_addon_install_path" -maxdepth 1 -type f -name '*.compose.yaml' ! -name 'compose.env' | head -n1)
  if [[ -z "${compose_file:-}" ]]; then
    msg_error "No valid compose file found in ${var_addon_install_path}!"
    exit 233
  fi
  compose_basename=$(basename "$compose_file")

  # check_legacy_db (inlined)
  if [[ "$compose_basename" == "sqlite.compose.yaml" || "$compose_basename" == "postgres.compose.yaml" ]]; then
    msg_error "Detected outdated ${APP} setup using SQLite or PostgreSQL (FerretDB v1)."
    echo -e "${YW}This configuration is no longer supported since Komodo v1.18.0.${CL}"
    echo -e "${YW}Please follow the migration guide:${CL}"
    echo -e "${BGN}https://github.com/community-scripts/ProxmoxVE/discussions/5689${CL}\n"
    exit 238
  fi

  msg_info "Updating ${APP}"
  local backup_file
  backup_file="${var_addon_install_path}/${compose_basename}.bak_$(date +%Y%m%d_%H%M%S)"
  cp "$compose_file" "$backup_file" || {
    msg_error "Failed to create backup of ${compose_basename}!"
    exit 235
  }
  cp "$var_addon_compose_env" "${var_addon_compose_env}.bak_$(date +%Y%m%d_%H%M%S)" 2> /dev/null || true

  if ! curl -fsSL "${var_addon_compose_base_url}/${compose_basename}" -o "$compose_file"; then
    msg_error "Failed to download ${compose_basename} from GitHub!"
    mv "$backup_file" "$compose_file"
    exit 115
  fi

  # === v2 migration: image tag (latest is deprecated) ===
  if grep -q '^COMPOSE_KOMODO_IMAGE_TAG=latest' "$var_addon_compose_env"; then
    msg_info "Migrating to Komodo v2 image tag"
    sed -i 's/^COMPOSE_KOMODO_IMAGE_TAG=latest/COMPOSE_KOMODO_IMAGE_TAG=2/' "$var_addon_compose_env"
    msg_ok "Migrated image tag to :2"
  fi

  # === v2 migration: DB credential variable names ===
  if grep -q '^KOMODO_DB_USERNAME=' "$var_addon_compose_env"; then
    msg_info "Migrating database credential variables"
    sed -i 's/^KOMODO_DB_USERNAME=/KOMODO_DATABASE_USERNAME=/' "$var_addon_compose_env"
    sed -i 's/^KOMODO_DB_PASSWORD=/KOMODO_DATABASE_PASSWORD=/' "$var_addon_compose_env"
    msg_ok "Migrated DB credential variables"
  fi

  # === v2 migration: remove deprecated passkey (replaced by PKI) ===
  if grep -q '^KOMODO_PASSKEY=' "$var_addon_compose_env"; then
    sed -i '/^KOMODO_PASSKEY=/d' "$var_addon_compose_env"
  fi

  # === v2 migration: ensure PERIPHERY_CORE_PUBLIC_KEYS is set ===
  if ! grep -q 'PERIPHERY_CORE_PUBLIC_KEYS' "$var_addon_compose_env"; then
    echo '## Use the public key generated by Core.' >> "$var_addon_compose_env"
    echo 'PERIPHERY_CORE_PUBLIC_KEYS=file:/config/keys/core.pub' >> "$var_addon_compose_env"
  fi

  # === ensure backups path is set ===
  if ! grep -q 'COMPOSE_KOMODO_BACKUPS_PATH=' "$var_addon_compose_env"; then
    echo 'COMPOSE_KOMODO_BACKUPS_PATH=/etc/komodo/backups' >> "$var_addon_compose_env"
  fi

  (cd "$var_addon_install_path" && $STD docker compose -p komodo -f "$compose_file" --env-file "$var_addon_compose_env" pull)
  (cd "$var_addon_install_path" && $STD docker compose -p komodo -f "$compose_file" --env-file "$var_addon_compose_env" up -d)
  msg_ok "Updated ${APP}"

  msg_ok "Updated successfully"
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"

  # find_compose_file (inlined — bundles contain only the hook body)
  local compose_file
  compose_file=$(find "$var_addon_install_path" -maxdepth 1 -type f -name '*.compose.yaml' ! -name 'compose.env' | head -n1)
  if [[ -z "${compose_file:-}" ]]; then
    msg_error "No valid compose file found in ${var_addon_install_path}!"
    exit 233
  fi

  msg_info "Stopping and removing Docker containers"
  (cd "$var_addon_install_path" && $STD docker compose -p komodo -f "$compose_file" --env-file "$var_addon_compose_env" down --volumes --remove-orphans)
  msg_ok "Stopped and removed Docker containers"

  rm -rf "$var_addon_install_path"
  msg_ok "${APP} has been uninstalled"
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
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon")
