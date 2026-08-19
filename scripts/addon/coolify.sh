#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://coolify.io/ | Github: https://github.com/coollabsio/coolify

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Coolify"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_install_path="${var_addon_install_path:-/data/coolify}"
var_addon_installer_url="${var_addon_installer_url:-https://cdn.coollabs.io/coolify/install.sh}"
var_addon_default_port="${var_addon_default_port:-8000}"

function install_script() {
  if [[ "$OS_FAMILY" != "debian" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu only)"
    exit 1
  fi

  if ! command -v docker &> /dev/null; then
    msg_info "Installing Docker"
    DOCKER_SKIP_UPDATES=true setup_docker
    msg_ok "Installed Docker"
  fi

  msg_info "Installing Dependencies"
  $STD apt install -y git openssl
  msg_ok "Installed Dependencies"

  msg_warn "WARNING: This will run an external installer from https://coolify.io/"
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
  $STD bash <(curl -fsSL "$var_addon_installer_url")
  msg_ok "Updated ${APP}"
  msg_ok "Updated successfully"
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"

  if command -v docker &> /dev/null; then
    msg_info "Stopping and removing Docker containers"
    (cd "${var_addon_install_path}/source" 2> /dev/null && $STD docker compose down --remove-orphans) || true
    docker ps -aq | xargs -r docker stop &> /dev/null || true
    docker ps -aq | xargs -r docker rm &> /dev/null || true
    $STD docker network prune -f || true
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
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon_lxc")
