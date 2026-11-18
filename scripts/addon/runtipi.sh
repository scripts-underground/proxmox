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

  if [[ ! "$var_addon_default_port" =~ ^[0-9]{1,5}$ ]] || ((10#$var_addon_default_port < 1 || 10#$var_addon_default_port > 65535)); then
    msg_error "Invalid Runtipi HTTP port: ${var_addon_default_port}"
    return 65
  fi
  if [[ -e "$var_addon_install_path" || -L "$var_addon_install_path" ]]; then
    msg_error "Runtipi install path is occupied; preserve it and use explicit adoption."
    return 65
  fi

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

  local installer installer_status=0 cleanup_status=0
  installer=$(mktemp "${TMPDIR}/runtipi-installer.XXXXXXXX") || return $?
  curl -fsSL "https://raw.githubusercontent.com/runtipi/runtipi/master/scripts/install.sh" -o "$installer" || installer_status=$?
  if [[ "$installer_status" == 0 && ! -s "$installer" ]]; then installer_status=251; fi
  if [[ "$installer_status" == 0 ]]; then bash -n "$installer" || installer_status=$?; fi

  # This closure is part of the install hook so every required status reaches
  # the exact stage owner, including dependency or external installer failures.
  _runtipi_install_from_stage() {
    if ! command -v docker &> /dev/null; then
      msg_info "Installing Docker"
      DOCKER_SKIP_UPDATES=true setup_docker || return $?
      msg_ok "Installed Docker"
    fi
    docker compose version &> /dev/null || return $?
    $STD apt update || return $?
    $STD apt install -y openssl || return $?
    mkdir -p "$var_addon_install_path/state" || return $?
    # The CLI's native SettingsSchema reads port before GenerateEnvFile/start.
    printf '{"port":%s}\n' "$((10#$var_addon_default_port))" > "$var_addon_install_path/state/settings.json" || return $?
    # Upstream --update suppresses its fixed "mkdir runtipi; cd runtipi" step;
    # download/start remain the same, now rooted at the selected directory.
    (cd "$var_addon_install_path" && $STD bash "$installer" --update) || return $?
    chmod 660 "$var_addon_install_path/state/settings.json" || return $?
  }
  msg_info "Installing ${APP} (this pulls Docker containers)"
  if [[ "$installer_status" == 0 ]]; then _runtipi_install_from_stage || installer_status=$?; fi
  rm -f -- "$installer" || cleanup_status=$?
  [[ "$installer_status" != 0 ]] || installer_status=$cleanup_status
  [[ "$installer_status" == 0 ]] || return "$installer_status"
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

  if ! command -v docker &> /dev/null || [[ ! -f "$var_addon_install_path/docker-compose.yml" || ! -f "$var_addon_install_path/.env" ]]; then
    msg_error "Docker or the installed Runtipi compose/environment is missing; retaining ${var_addon_install_path}"
    return 1
  fi

  if [[ -f "${var_addon_install_path}/runtipi-cli" ]]; then
    msg_info "Stopping ${APP}"
    (cd "$var_addon_install_path" && $STD ./runtipi-cli stop)
    msg_ok "Stopped ${APP}"
  fi

  local -a compose_files=(-f "$var_addon_install_path/docker-compose.yml")
  [[ ! -f "$var_addon_install_path/user-config/tipi-compose.yml" ]] || compose_files+=(-f "$var_addon_install_path/user-config/tipi-compose.yml")
  msg_info "Removing Docker containers"
  $STD docker compose --project-name runtipi "${compose_files[@]}" --env-file "$var_addon_install_path/.env" down --remove-orphans
  msg_ok "Removed Docker containers"

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
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon_lxc") --script-id runtipi -- "$@"
