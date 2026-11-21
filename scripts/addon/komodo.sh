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

  if [[ ! "$var_addon_default_port" =~ ^[0-9]{1,5}$ ]] || ((10#$var_addon_default_port < 1 || 10#$var_addon_default_port > 65535)); then
    msg_error "Invalid Komodo HTTP port: ${var_addon_default_port}"
    return 65
  fi
  local occupied
  for occupied in "$var_addon_compose_env" "$var_addon_install_path/.komodo-compose" "$var_addon_install_path/"*.compose.yaml; do
    if [[ -e "$occupied" || -L "$occupied" ]]; then
      msg_error "Komodo configuration already exists at ${occupied}; preserve it and use explicit adoption."
      return 65
    fi
  done

  if ! command -v docker > /dev/null 2>&1; then
    msg_info "Installing Docker"
    DOCKER_SKIP_UPDATES=true setup_docker
    msg_ok "Installed Docker"
  fi
  if ! docker compose version > /dev/null 2>&1; then
    msg_error "Docker Compose plugin is not available. Please install it before running this script. Exiting."
    exit 1
  fi
  addon_compose_require --no-interpolate --no-env-resolution --no-path-resolution || return $?
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

  msg_info "Preparing compose and private environment"
  local compose_stage env_stage compose_status
  compose_stage=$(mktemp -d "${var_addon_install_path}/.komodo-compose.XXXXXXXX")
  mkdir -p "$(dirname "$var_addon_compose_env")"
  if env_stage=$(mktemp -d "$(dirname "$var_addon_compose_env")/.komodo-env.XXXXXXXX"); then :; else
    compose_status=$?
    rm -rf -- "$compose_stage"
    return "$compose_status"
  fi
  # Prepare every producer before publishing configuration. Keep interpolation
  # expressions live so future image/env changes remain operator-owned.
  if curl -fsSL "${var_addon_compose_base_url}/${DB_COMPOSE_FILE}" -o "$compose_stage/source.yaml" &&
    curl -fsSL "${var_addon_compose_base_url}/compose.env" -o "$env_stage/compose.env" &&
    [[ -s "$compose_stage/source.yaml" && -s "$env_stage/compose.env" ]]; then
    :
  else
    compose_status=$?
    rm -rf -- "$compose_stage" "$env_stage"
    return "$compose_status"
  fi

  local db_password webhook_secret jwt_secret
  db_password=$(openssl rand -hex 16)
  KOMODO_ADMIN_PASSWORD=$(openssl rand -hex 8)
  webhook_secret=$(openssl rand -hex 24)
  jwt_secret=$(openssl rand -hex 24)

  if sed -i -e 's/^KOMODO_DATABASE_USERNAME=.*/KOMODO_DATABASE_USERNAME=komodo_admin/' \
    -e "s/^KOMODO_DATABASE_PASSWORD=.*/KOMODO_DATABASE_PASSWORD=${db_password}/" \
    -e "s/^KOMODO_INIT_ADMIN_PASSWORD=.*/KOMODO_INIT_ADMIN_PASSWORD=${KOMODO_ADMIN_PASSWORD}/" \
    -e "s/^KOMODO_WEBHOOK_SECRET=.*/KOMODO_WEBHOOK_SECRET=${webhook_secret}/" \
    -e "s/^KOMODO_JWT_SECRET=.*/KOMODO_JWT_SECRET=${jwt_secret}/" "$env_stage/compose.env" &&
    addon_compose_source --project-directory "$var_addon_install_path" --env-file "$env_stage/compose.env" -f "$compose_stage/source.yaml" > "$compose_stage/source.json" &&
    jq -e --arg port "$var_addon_default_port" --arg env "$var_addon_compose_env" --arg original "$var_addon_install_path/compose.env" '
      .services.core.ports |= map(if .target == 9120 then .published = $port else . end) |
      (.services[] | select(has("env_file")) | .env_file) |= map(if .path == $original or .path == "compose.env" or .path == "./compose.env" then .path = $env else . end) |
      # Without interpolation Compose cannot classify these documented host
      # directories. Retain their expressions in explicit long-form binds.
      (.services[].volumes[]? | select(.source == "${COMPOSE_KOMODO_BACKUPS_PATH}" or .source == "${PERIPHERY_ROOT_DIRECTORY:-/etc/komodo}")) |=
        (.type = "bind" | del(.volume) | .bind = {"create_host_path": true})
    ' "$compose_stage/source.json" > "$compose_stage/compose.json" &&
    chmod 600 "$env_stage/compose.env" "$compose_stage/compose.json" &&
    jq --arg live "$var_addon_compose_env" --arg stage "$env_stage/compose.env" '
      (.services[] | select(has("env_file")) | .env_file) |= map(if .path == $live then .path = $stage else . end)
    ' "$compose_stage/compose.json" > "$compose_stage/validation.json" &&
    docker compose --project-directory "$var_addon_install_path" --env-file "$env_stage/compose.env" -f "$compose_stage/validation.json" config -q &&
    (
      umask 077
      printf '%s\n' "$DB_COMPOSE_FILE" > "$compose_stage/selection"
    ) &&
    addon_publish_owned_file "$env_stage/compose.env" "$var_addon_compose_env" &&
    ln -T -- "$compose_stage/compose.json" "${var_addon_install_path}/${DB_COMPOSE_FILE}" &&
    ln -T -- "$compose_stage/selection" "$var_addon_install_path/.komodo-compose"; then
    rm -rf -- "$compose_stage" "$env_stage"
  else
    compose_status=$?
    if [[ "$var_addon_compose_env" -ef "$env_stage/compose.env" ]]; then rm -f -- "$var_addon_compose_env"; fi
    if [[ "$var_addon_install_path/$DB_COMPOSE_FILE" -ef "$compose_stage/compose.json" ]]; then rm -f -- "$var_addon_install_path/$DB_COMPOSE_FILE"; fi
    if [[ "$var_addon_install_path/.komodo-compose" -ef "$compose_stage/selection" ]]; then rm -f -- "$var_addon_install_path/.komodo-compose"; fi
    rm -rf -- "$compose_stage" "$env_stage"
    addon_remove_owned_file "$var_addon_compose_env" || msg_warn "Komodo environment custody retained for explicit recovery"
    return "$compose_status"
  fi
  msg_ok "Configured compose and environment"

  msg_info "Starting ${APP}"
  (cd "$var_addon_install_path" && $STD docker compose -p komodo -f "${var_addon_install_path}/${DB_COMPOSE_FILE}" --env-file "$var_addon_compose_env" up -d)
  msg_ok "Started ${APP}"

  (
    umask 077
    {
      echo "${APP} Credentials"
      echo ""
      echo "Admin User    : admin"
      echo "Admin Password: ${KOMODO_ADMIN_PASSWORD}"
    } >> ~/komodo.creds
  )
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

  # Selection is plain data, never sourced. Old installs can be adopted only
  # when exactly one compose file establishes the choice without guessing.
  local compose_file compose_basename candidate
  local -a compose_choices=()
  if [[ -e "$var_addon_install_path/.komodo-compose" ]]; then
    mapfile -t compose_choices < "$var_addon_install_path/.komodo-compose"
    if ((${#compose_choices[@]} != 1)) || [[ -z "${compose_choices[0]}" || "${compose_choices[0]}" == */* ]]; then
      msg_error "Invalid Komodo compose selection"
      return 233
    fi
    compose_file="$var_addon_install_path/${compose_choices[0]}"
  else
    for candidate in "$var_addon_install_path/"*.compose.yaml; do
      [[ ! -f "$candidate" ]] || compose_choices+=("$candidate")
    done
    if ((${#compose_choices[@]} != 1)); then
      msg_error "Komodo compose selection is missing or ambiguous; record the chosen filename in ${var_addon_install_path}/.komodo-compose"
      return 233
    fi
    compose_file=${compose_choices[0]}
  fi
  [[ -f "$compose_file" ]] || {
    msg_error "Selected Komodo compose file is missing: ${compose_file}"
    return 233
  }
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
  (
    umask 077
    cp "$compose_file" "$backup_file"
  ) || {
    msg_error "Failed to create backup of ${compose_basename}!"
    exit 235
  }
  (
    umask 077
    cp "$var_addon_compose_env" "${var_addon_compose_env}.bak_$(date +%Y%m%d_%H%M%S)"
  )

  # Only our own unchanged generated environment can advance its independent
  # custody. Legacy/operator files keep their existing migration behavior without
  # becoming uninstall-owned. Prepare owned edits off-line and refuse a changed
  # live preimage instead of assigning operator bytes to the new receipt.
  local live_env=$var_addon_compose_env owned_env_identity env_candidate='' env_copy_hash env_status
  addon_owned_file_identity owned_env_identity "$live_env" || return $?
  local var_addon_compose_env=$live_env
  if [[ -n "$owned_env_identity" ]]; then
    env_candidate=$(mktemp "${live_env%/*}/.komodo-env-update.XXXXXXXX") || return $?
    if cp -p -- "$live_env" "$env_candidate" && env_copy_hash=$(sha256sum < "$env_candidate") &&
      [[ "${env_copy_hash%% *}" == "${owned_env_identity##*:}" ]]; then :; else
      env_status=$?
      rm -f -- "$env_candidate" || msg_warn "Komodo environment preparation retained at $env_candidate"
      return "$env_status"
    fi
    var_addon_compose_env=$env_candidate
  fi
  if [[ ! -e "$var_addon_install_path/.komodo-compose" ]]; then
    (
      umask 077
      printf '%s\n' "$compose_basename" > "$var_addon_install_path/.komodo-compose"
    )
  fi

  # === v2 migration: image tag (latest is deprecated) ===
  if grep -q '^COMPOSE_KOMODO_IMAGE_TAG=latest' "$var_addon_compose_env"; then
    msg_info "Migrating to Komodo v2 image tag"
    sed -i 's/^COMPOSE_KOMODO_IMAGE_TAG=latest/COMPOSE_KOMODO_IMAGE_TAG=2/' "$var_addon_compose_env"
    msg_ok "Migrated image tag to :2"
  fi

  # Native dotenv parsing owns effective key presence, including export/space,
  # multiline and explicitly empty assignments. Probe presence only: never emit
  # parsed credential values or invent a second dotenv serializer.
  local credential legacy current aliases dotenv_stage dotenv_status
  dotenv_stage=$(_tools_stage_dir komodo-dotenv) || return $?
  if jq -n '{services:{probe:{image:"scratch",environment:{
      KOMODO_DB_USERNAME:"${KOMODO_DB_USERNAME+present}",
      KOMODO_DB_PASSWORD:"${KOMODO_DB_PASSWORD+present}",
      KOMODO_DATABASE_USERNAME:"${KOMODO_DATABASE_USERNAME+present}",
      KOMODO_DATABASE_PASSWORD:"${KOMODO_DATABASE_PASSWORD+present}"
    }}}}' > "$dotenv_stage/probe.json" &&
    docker compose --project-directory "$var_addon_install_path" --env-file "$var_addon_compose_env" -f "$dotenv_stage/probe.json" config --format json > "$dotenv_stage/parsed.json" &&
    aliases=$(jq -ce '.services.probe.environment | select(length == 4 and all(.[]; . == "" or . == "present"))' "$dotenv_stage/parsed.json"); then :; else
    dotenv_status=$?
    rm -rf -- "$dotenv_stage"
    [[ -z "$env_candidate" ]] || msg_warn "Komodo environment preparation retained at $env_candidate"
    return "$dotenv_status"
  fi
  rm -rf -- "$dotenv_stage" || return $?
  for credential in USERNAME PASSWORD; do
    legacy="KOMODO_DB_${credential}" current="KOMODO_DATABASE_${credential}"
    if jq -e --arg current "$current" --arg legacy "$legacy" '.[$current] == "" and .[$legacy] == "present"' <<< "$aliases" > /dev/null; then
      # Compose resolves this alias without re-parsing the credential as dotenv
      # source, preserving literal dollar, backslash and newline bytes.
      printf '\n%s=${%s}\n' "$current" "$legacy" >> "$var_addon_compose_env"
    fi
  done

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

  if [[ -n "$env_candidate" ]]; then
    if addon_replace_owned_file "$env_candidate" "$live_env" "$owned_env_identity"; then :; else
      env_status=$?
      msg_warn "Komodo environment preparation retained at $env_candidate"
      return "$env_status"
    fi
    var_addon_compose_env=$live_env
  fi

  (cd "$var_addon_install_path" && $STD docker compose -p komodo -f "$compose_file" --env-file "$var_addon_compose_env" pull)
  (cd "$var_addon_install_path" && $STD docker compose -p komodo -f "$compose_file" --env-file "$var_addon_compose_env" up -d)
  msg_ok "Updated ${APP}"

  msg_ok "Updated successfully"
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"

  local compose_file candidate
  local -a compose_choices=()
  if [[ -e "$var_addon_install_path/.komodo-compose" ]]; then
    mapfile -t compose_choices < "$var_addon_install_path/.komodo-compose"
    if ((${#compose_choices[@]} != 1)) || [[ -z "${compose_choices[0]}" || "${compose_choices[0]}" == */* ]]; then
      msg_error "Invalid Komodo compose selection"
      return 233
    fi
    compose_file="$var_addon_install_path/${compose_choices[0]}"
  else
    for candidate in "$var_addon_install_path/"*.compose.yaml; do
      [[ ! -f "$candidate" ]] || compose_choices+=("$candidate")
    done
    if ((${#compose_choices[@]} != 1)); then
      msg_error "Komodo compose selection is missing or ambiguous; record the chosen filename in ${var_addon_install_path}/.komodo-compose"
      return 233
    fi
    compose_file=${compose_choices[0]}
  fi
  [[ -f "$compose_file" ]] || {
    msg_error "Selected Komodo compose file is missing: ${compose_file}"
    return 233
  }

  msg_info "Stopping and removing Docker containers"
  (cd "$var_addon_install_path" && $STD docker compose -p komodo -f "$compose_file" --env-file "$var_addon_compose_env" down --volumes --remove-orphans)
  msg_ok "Stopped and removed Docker containers"

  addon_remove_owned_file "$var_addon_compose_env"
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
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon_lxc") --script-id komodo -- "$@"
