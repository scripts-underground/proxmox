#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://dokploy.com/ | Github: https://github.com/Dokploy/dokploy

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Dokploy"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_install_path="${var_addon_install_path:-/etc/dokploy}"
var_addon_installer_url="${var_addon_installer_url:-https://dokploy.com/install.sh}"
var_addon_default_port="${var_addon_default_port:-3000}"

function install_script() {
  if [[ "$OS_FAMILY" != "debian" && "$OS_FAMILY" != "alpine" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu and Alpine only)"
    exit 1
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

  msg_info "Installing Dependencies"
  if [[ "$OS_FAMILY" == "alpine" ]]; then
    $STD apk add --no-cache git openssl
  else
    $STD apt update
    $STD apt install -y git openssl redis
  fi
  msg_ok "Installed Dependencies"

  msg_warn "WARNING: This will run an external installer from https://dokploy.com/"
  msg_warn "The following code is NOT maintained or audited by our repository."
  msg_warn "Review: ${var_addon_installer_url}"
  echo ""
  read -erp "${TAB}Do you want to continue? (y/N): " CONFIRM || true
  if [[ ! "${CONFIRM,,}" =~ ^(y|yes)$ ]]; then
    msg_warn "Installation cancelled. Exiting."
    exit 0
  fi

  msg_info "Installing ${APP} (this installs Docker and pulls containers)"
  $STD bash <(curl -fsSL "$var_addon_installer_url")
  msg_ok "Installed ${APP}"
}

function post_install_script() {
  echo ""
  msg_ok "${APP} installed successfully"
  echo -e "${INFO}${YW}Web UI:${CL} ${BGN}http://${LOCAL_IP}:${var_addon_default_port}${CL}"
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
}

function update_script() {
  if [[ ! -d "$var_addon_install_path" ]]; then
    msg_error "No ${APP} installation found (${var_addon_install_path} missing)"
    exit 1
  fi

  msg_info "Updating ${APP}"
  $STD curl -fsSL "$var_addon_installer_url" | bash -s update
  msg_ok "Updated ${APP}"
  msg_ok "Updated successfully"
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"

  if command -v docker &> /dev/null; then
    msg_info "Stopping and removing Dokploy Docker resources"
    local services containers networks volumes secrets name
    # Dokploy's installer creates named Swarm services, not a Compose project.
    # Check each inventory before effects; failed queries are not absence.
    services=$(docker service ls --format '{{.Name}}')
    containers=$(docker container ls -a --format '{{.Names}}')
    networks=$(docker network ls --format '{{.Name}}')
    volumes=$(docker volume ls --format '{{.Name}}')
    secrets=$(docker secret ls --format '{{.Name}}')
    for name in dokploy dokploy-postgres dokploy-redis dokploy-traefik; do
      if grep -Fxq "$name" <<< "$services"; then
        # Converge to zero tasks before removing the service so it cannot
        # recreate a container or keep a volume/network busy during cleanup.
        $STD docker service scale --detach=false "${name}=0"
        $STD docker service rm "$name"
      fi
    done
    if grep -Fxq dokploy-traefik <<< "$containers"; then
      $STD docker container rm -f dokploy-traefik
    fi
    if grep -Fxq dokploy-network <<< "$networks"; then
      $STD docker network rm dokploy-network
    fi
    for name in dokploy dokploy-postgres dokploy-redis; do
      if grep -Fxq "$name" <<< "$volumes"; then
        $STD docker volume rm "$name"
      fi
    done
    for name in dokploy_postgres_password dokploy_auth_secret; do
      if grep -Fxq "$name" <<< "$secrets"; then
        $STD docker secret rm "$name"
      fi
    done
    msg_ok "Stopped and removed Dokploy Docker resources"
  else
    msg_error "Docker is unavailable; retaining ${var_addon_install_path}"
    return 1
  fi

  msg_ok "${APP} has been uninstalled"
  # Deployments can bind-mount files beneath this root, independently of the
  # core Swarm services. A directory location does not prove data ownership.
  local remove_command
  printf -v remove_command 'rm -rf -- %q' "$var_addon_install_path"
  msg_warn "Retained directory ${var_addon_install_path}; it may contain deployment data."
  msg_warn "To remove it manually: ${remove_command}"
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
