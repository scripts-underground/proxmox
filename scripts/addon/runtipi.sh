#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://runtipi.io/ | Github: https://github.com/runtipi/runtipi

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Runtipi"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_install_path="${var_addon_install_path:-/opt/runtipi}"
var_addon_default_port="${var_addon_default_port:-80}"

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
  if ! docker compose version &> /dev/null; then
    msg_error "Docker Compose plugin is not available. Please install it before running this script. Exiting."
    exit 1
  fi
  msg_ok "Docker $(docker --version | cut -d' ' -f3 | tr -d ',') and Docker Compose are available"

  msg_info "Installing Dependencies"
  $STD apt update
  $STD apt install -y openssl
  msg_ok "Installed Dependencies"

  msg_warn "WARNING: This will run an external installer from https://runtipi.io/"
  msg_warn "The following code is NOT maintained or audited by our repository."
  msg_warn "Review: https://raw.githubusercontent.com/runtipi/runtipi/master/scripts/install.sh"
  echo ""
  echo -n "${TAB}Do you want to continue? (y/N): "
  read -r confirm || true
  if [[ ! "${confirm,,}" =~ ^(y|yes)$ ]]; then
    msg_error "Installation cancelled by user"
    exit 1
  fi

  msg_info "Installing ${APP} (this pulls Docker containers)"
  DOCKER_CONFIG_PATH='/etc/docker/daemon.json'
  mkdir -p "$(dirname "$DOCKER_CONFIG_PATH")"
  [[ ! -f "$DOCKER_CONFIG_PATH" ]] && echo -e '{\n  "log-driver": "journald"\n}' > "$DOCKER_CONFIG_PATH"
  curl -fsSL "https://raw.githubusercontent.com/runtipi/runtipi/master/scripts/install.sh" -o /opt/install.sh
  chmod +x /opt/install.sh
  (cd /opt && $STD ./install.sh)
  chmod 660 /opt/runtipi/state/settings.json 2> /dev/null || true
  rm -f /opt/install.sh
  msg_ok "Installed ${APP}"
}

function post_install_script() {
  echo ""
  msg_ok "${APP} installed successfully"
  echo -e "${INFO}${YW}Web UI:${CL} ${BGN}http://${LOCAL_IP}:${var_addon_default_port}${CL}"
  echo -e "${INFO}${YW}Install path:${CL} ${var_addon_install_path}"
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
}

function update_script() {
  if [[ ! -d "$var_addon_install_path" ]]; then
    msg_error "${APP} is not installed. Nothing to update."
    exit 1
  fi

  msg_info "Updating ${APP}"
  (cd "$var_addon_install_path" && $STD ./runtipi-cli update latest)
  msg_ok "Updated ${APP}"
  msg_ok "Updated successfully"
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"

  if [[ -f "${var_addon_install_path}/runtipi-cli" ]]; then
    msg_info "Stopping ${APP}"
    (cd "$var_addon_install_path" && $STD ./runtipi-cli stop 2> /dev/null || true)
    msg_ok "Stopped ${APP}"
  fi

  if command -v docker &> /dev/null; then
    msg_info "Removing Docker containers"
    (cd "$var_addon_install_path" 2> /dev/null && $STD docker compose down --remove-orphans 2> /dev/null || true)
    msg_ok "Removed Docker containers"
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
