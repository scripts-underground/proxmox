#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: summoningpixels
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/getarcaneapp/arcane

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Arcane"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_install_path="${var_addon_install_path:-/opt/arcane}"
var_addon_compose_file="${var_addon_compose_file:-${var_addon_install_path}/compose.yaml}"
var_addon_env_file="${var_addon_env_file:-${var_addon_install_path}/.env}"
var_addon_proj_dir="${var_addon_proj_dir:-/etc/arcane/projects}"
var_addon_builds_dir="${var_addon_builds_dir:-/etc/arcane/builds}"
var_addon_compose_url="${var_addon_compose_url:-https://raw.githubusercontent.com/getarcaneapp/arcane/refs/heads/main/docker/examples/compose.basic.yaml}"
var_addon_env_url="${var_addon_env_url:-https://raw.githubusercontent.com/getarcaneapp/arcane/refs/heads/main/.env.example}"
var_addon_default_port="${var_addon_default_port:-3552}"

function install_script() {
  if [[ "$OS_FAMILY" != "debian" && "$OS_FAMILY" != "alpine" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu and Alpine only)"
    return 1
  fi
  if [[ ! "$var_addon_default_port" =~ ^[0-9]{1,5}$ ]] || ((10#$var_addon_default_port < 1 || 10#$var_addon_default_port > 65535)); then
    msg_error "Invalid Arcane HTTP port: ${var_addon_default_port}"
    return 65
  fi
  if [[ "$var_addon_compose_file" == "$var_addon_env_file" || -e "$var_addon_compose_file" || -L "$var_addon_compose_file" || -e "$var_addon_env_file" || -L "$var_addon_env_file" ]]; then
    msg_error "Arcane compose or environment path is already occupied; preserve it and use explicit adoption."
    return 65
  fi

  if ! command -v docker &> /dev/null; then
    msg_info "Installing Docker"
    if [[ "$OS_FAMILY" == "alpine" ]]; then
      $STD apk add --no-cache docker docker-cli-compose
      $STD rc-update add docker default
      $STD rc-service docker start
    else
      DOCKER_SKIP_UPDATES=true setup_docker
    fi
    msg_ok "Installed Docker"
  fi
  if ! docker compose version &> /dev/null; then
    msg_error "Docker Compose plugin is not available. Please install it before running this script. Exiting."
    exit 1
  fi
  msg_ok "Docker $(docker --version | cut -d' ' -f3 | tr -d ',') and Docker Compose are available"

  msg_info "Creating install directory"
  mkdir -p "$var_addon_install_path"
  msg_ok "Created ${var_addon_install_path}"

  ensure_dependencies openssl
  local encryption_key
  encryption_key=$(openssl rand -hex 16)

  # Arcane drops root and runs as UID/GID 65532 by default (Dockerfile default,
  # see backend/pkg/libarcane/startup/runtime_identity.go), so bind-mounted
  # host directories must be owned by that UID or the container can't write to them.
  msg_info "Creating stacks directory"
  if [[ ! -e "$var_addon_proj_dir" ]]; then
    mkdir -p "$var_addon_proj_dir"
    chown 65532:65532 "$var_addon_proj_dir"
  fi
  msg_ok "Created ${var_addon_proj_dir}"

  msg_info "Creating builds directory"
  if [[ ! -e "$var_addon_builds_dir" ]]; then
    mkdir -p "$var_addon_builds_dir"
    chown 65532:65532 "$var_addon_builds_dir"
  fi
  msg_ok "Created ${var_addon_builds_dir}"

  msg_info "Preparing Docker Compose and environment files"
  mkdir -p "$(dirname "$var_addon_compose_file")" "$(dirname "$var_addon_env_file")"
  local compose_stage env_stage prepare_status
  compose_stage=$(mktemp -d "$(dirname "$var_addon_compose_file")/.arcane-compose.XXXXXXXX")
  if env_stage=$(mktemp -d "$(dirname "$var_addon_env_file")/.arcane-env.XXXXXXXX"); then :; else
    prepare_status=$?
    rm -rf -- "$compose_stage"
    return "$prepare_status"
  fi
  # Native Compose owns YAML and environment interpretation. No incomplete
  # transport or invalid source is published into either selected live path.
  if curl -fsSL "$var_addon_compose_url" -o "$compose_stage/source.yaml" &&
    curl -fsSL "$var_addon_env_url" -o "$env_stage/runtime.env" &&
    [[ -s "$compose_stage/source.yaml" && -s "$env_stage/runtime.env" ]] &&
    sed -i -e "s|^ARCANE_APP_URL=.*|ARCANE_APP_URL=http://localhost:${var_addon_default_port}|" \
      -e "s|^ARCANE_ENCRYPTION_KEY=.*|ARCANE_ENCRYPTION_KEY=${encryption_key}|" "$env_stage/runtime.env" &&
    docker compose --project-directory "$var_addon_install_path" --env-file "$env_stage/runtime.env" -f "$compose_stage/source.yaml" config --format json > "$compose_stage/source.json" &&
    jq -e --arg port "$var_addon_default_port" \
      --arg projects "$var_addon_proj_dir" --arg builds "$var_addon_builds_dir" --arg env "$var_addon_env_file" '
      .services.arcane.ports |= map(if .target == 3552 then .published = $port else . end) |
      .services.arcane.environment.ARCANE_ENCRYPTION_KEY = "${ARCANE_ENCRYPTION_KEY}" |
      .services.arcane.environment.ARCANE_PROJECTS_DIRECTORY = $projects |
      .services.arcane.environment.ARCANE_APP_URL = "${ARCANE_APP_URL}" |
      .services.arcane.volumes |= map(
        if .source == "/host/path/to/projects" then .source = $projects | .target = $projects
        elif .source == "/host/path/to/builds" then .source = $builds else . end) |
      .services.arcane.env_file = [{path: $env, required: true}]
    ' "$compose_stage/source.json" > "$compose_stage/compose.json" &&
    chmod 600 "$env_stage/runtime.env" "$compose_stage/compose.json" &&
    docker compose --project-directory "$var_addon_install_path" --env-file "$env_stage/runtime.env" -f "$compose_stage/compose.json" config --no-env-resolution -q &&
    mv -f "$env_stage/runtime.env" "$var_addon_env_file" &&
    mv -f "$compose_stage/compose.json" "$var_addon_compose_file"; then
    rm -rf -- "$compose_stage" "$env_stage"
  else
    prepare_status=$?
    rm -rf -- "$compose_stage" "$env_stage"
    return "$prepare_status"
  fi
  msg_ok "Prepared Docker Compose and environment files"

  msg_info "Starting ${APP}"
  $STD docker compose --project-directory "$var_addon_install_path" --env-file "$var_addon_env_file" -f "$var_addon_compose_file" up -d
  msg_ok "Started ${APP}"
}

function post_install_script() {
  echo ""
  msg_ok "${APP} installed successfully"
  echo -e "${INFO}${YW}Web UI:${CL} ${BGN}http://${LOCAL_IP}:${var_addon_default_port}${CL}"
  echo -e "${INFO}${YW}Login:${CL} ${GN}arcane${CL} / ${GN}arcane-admin${CL} (you'll be prompted to change the password on first access)"
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
}

function update_script() {
  if [[ ! -f "$var_addon_compose_file" ]]; then
    msg_error "No ${APP} installation found (${var_addon_compose_file} missing)"
    exit 1
  fi

  msg_info "Pulling latest ${APP} image"
  $STD docker compose --project-directory "$var_addon_install_path" --env-file "$var_addon_env_file" -f "$var_addon_compose_file" pull
  msg_ok "Pulled latest image"

  msg_info "Restarting ${APP}"
  $STD docker compose --project-directory "$var_addon_install_path" --env-file "$var_addon_env_file" -f "$var_addon_compose_file" up -d --remove-orphans
  msg_ok "Restarted ${APP}"
  msg_ok "Updated successfully"
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"

  if [[ ! -f "$var_addon_compose_file" ]]; then
    msg_error "No ${APP} installation found (${var_addon_compose_file} missing)"
    return 1
  fi
  msg_info "Stopping and removing Docker containers"
  $STD docker compose --project-directory "$var_addon_install_path" --env-file "$var_addon_env_file" -f "$var_addon_compose_file" down --volumes --remove-orphans
  msg_ok "Stopped and removed Docker containers"

  rm -f -- "$var_addon_compose_file" "$var_addon_env_file"
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
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon_lxc") --script-id arcane -- "$@"
