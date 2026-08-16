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

  # Generate secrets and config values
  local ENCRYPTION_KEY JWT_SECRET
  ENCRYPTION_KEY=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c32)
  JWT_SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c32)

  # Arcane drops root and runs as UID/GID 65532 by default (Dockerfile default,
  # see backend/pkg/libarcane/startup/runtime_identity.go), so bind-mounted
  # host directories must be owned by that UID or the container can't write to them.
  msg_info "Creating stacks directory"
  mkdir -p "$var_addon_proj_dir"
  chown -R 65532:65532 "$var_addon_proj_dir"
  msg_ok "Created ${var_addon_proj_dir}"

  msg_info "Creating builds directory"
  mkdir -p "$var_addon_builds_dir"
  chown -R 65532:65532 "$var_addon_builds_dir"
  msg_ok "Created ${var_addon_builds_dir}"

  msg_info "Downloading Docker Compose file"
  curl -fsSL "$var_addon_compose_url" -o "$var_addon_compose_file"
  msg_ok "Downloaded Docker Compose file"

  msg_info "Downloading .env file"
  curl -fsSL "$var_addon_env_url" -o "$var_addon_env_file"
  chmod 600 "$var_addon_env_file"
  msg_ok "Downloaded .env file"

  msg_info "Configuring compose and env files"
  sed -i '/^[[:space:]]*#/!s|/host/path/to/projects|'"$var_addon_proj_dir"'|g' "$var_addon_compose_file"
  sed -i '/^[[:space:]]*#/!s|/host/path/to/builds|'"$var_addon_builds_dir"'|g' "$var_addon_compose_file"
  sed -i '/^[[:space:]]*#/!s|ENCRYPTION_KEY=.*|ENCRYPTION_KEY='"$ENCRYPTION_KEY"'|g' "$var_addon_compose_file"
  sed -i '/^[[:space:]]*#/!s|JWT_SECRET=.*|JWT_SECRET='"$JWT_SECRET"'|g' "$var_addon_compose_file"
  sed -i '/^[[:space:]]*#/!s|APP_URL=.*|APP_URL=http://localhost:'"$var_addon_default_port"'|g' "$var_addon_env_file"
  sed -i '/^[[:space:]]*#/!s|ENCRYPTION_KEY=.*|#&|g' "$var_addon_env_file"
  sed -i '/^[[:space:]]*#/!s|JWT_SECRET=.*|#&|g' "$var_addon_env_file"
  msg_ok "Configured compose and env files"

  msg_info "Starting ${APP}"
  (cd "$var_addon_install_path" && $STD docker compose up -d)
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

  chown -R 65532:65532 "$var_addon_proj_dir" "$var_addon_builds_dir" 2> /dev/null || true

  msg_info "Pulling latest ${APP} image"
  (cd "$var_addon_install_path" && $STD docker compose pull)
  msg_ok "Pulled latest image"

  msg_info "Restarting ${APP}"
  (cd "$var_addon_install_path" && $STD docker compose up -d --remove-orphans)
  msg_ok "Restarted ${APP}"
  msg_ok "Updated successfully"
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"

  if [[ -f "$var_addon_compose_file" ]]; then
    msg_info "Stopping and removing Docker containers"
    (cd "$var_addon_install_path" && $STD docker compose down --volumes --remove-orphans)
    msg_ok "Stopped and removed Docker containers"
  fi

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
