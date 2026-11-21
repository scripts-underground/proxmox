#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/portainer/portainer

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Portainer"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_install_path="${var_addon_install_path:-/opt/portainer}"
var_addon_compose_file="${var_addon_compose_file:-${var_addon_install_path:-/opt/portainer}/compose.yaml}"
var_addon_compose_url="${var_addon_compose_url:-https://downloads.portainer.io/ce-sts/portainer-compose.yaml}"
var_addon_default_port="${var_addon_default_port:-9443}"

function install_script() {
  if [[ "$OS_FAMILY" != "debian" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu only)"
    exit 1
  fi

  if [[ ! "$var_addon_default_port" =~ ^[0-9]{1,5}$ ]] || ((10#$var_addon_default_port < 1 || 10#$var_addon_default_port > 65535)); then
    msg_error "Invalid Portainer HTTPS port: ${var_addon_default_port}"
    return 65
  fi
  if [[ -e "$var_addon_compose_file" || -L "$var_addon_compose_file" || -e /etc/systemd/system/portainer.service || -L /etc/systemd/system/portainer.service ]]; then
    msg_error "Portainer compose or service path is already occupied; preserve it and use explicit adoption."
    return 65
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
  addon_compose_require --no-interpolate --no-env-resolution --no-path-resolution || return $?
  msg_ok "Docker $(docker --version | cut -d' ' -f3 | tr -d ',') and Docker Compose are available"

  if docker container inspect portainer &> /dev/null; then
    msg_error "A container named 'portainer' already exists and is not managed by this addon. Remove it first or update it directly."
    exit 1
  fi

  msg_info "Creating install directory"
  mkdir -p "$var_addon_install_path"
  msg_ok "Created ${var_addon_install_path}"

  msg_info "Downloading Docker Compose file"
  mkdir -p "$(dirname "$var_addon_compose_file")"
  local compose_stage compose_status
  compose_stage=$(mktemp -d "$(dirname "$var_addon_compose_file")/.portainer-compose.XXXXXXXX")
  # Preserve editable expressions, env_file and project-relative paths. Resolve a
  # separate model for validation; publish only the unresolved source model.
  if curl -fsSL "$var_addon_compose_url" -o "$compose_stage/source.yaml" &&
    addon_compose_source --project-directory "$var_addon_install_path" -f "$compose_stage/source.yaml" > "$compose_stage/source.json" &&
    jq -e --arg port "$var_addon_default_port" '
      .services.portainer.ports |= map(if .target == 9443 then .published = $port else . end)
    ' "$compose_stage/source.json" > "$compose_stage/compose.json" &&
    docker compose --project-directory "$var_addon_install_path" -f "$compose_stage/compose.json" config -q &&
    mv -f "$compose_stage/compose.json" "$var_addon_compose_file"; then
    rm -rf -- "$compose_stage"
  else
    compose_status=$?
    rm -rf -- "$compose_stage"
    return "$compose_status"
  fi
  msg_ok "Downloaded Docker Compose file"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/portainer.service
[Unit]
Description=${APP} (Docker Compose)
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${var_addon_install_path}
ExecStart=/usr/bin/docker compose --project-directory "${var_addon_install_path}" -f "${var_addon_compose_file}" up -d
ExecStop=/usr/bin/docker compose --project-directory "${var_addon_install_path}" -f "${var_addon_compose_file}" down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now portainer
  msg_ok "Created Service"
}

function post_install_script() {
  echo ""
  msg_ok "${APP} installed successfully"
  echo -e "${INFO}${YW}Web UI:${CL} ${BGN}https://${LOCAL_IP}:${var_addon_default_port}${CL}"
  echo -e "${INFO}${YW}Note:${CL} on first access, you'll be prompted to create an admin account"
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
}

function update_script() {
  if [[ ! -f "$var_addon_compose_file" ]]; then
    msg_error "No ${APP} installation found (${var_addon_compose_file} missing)"
    exit 1
  fi

  msg_info "Pulling latest ${APP} image"
  $STD docker compose --project-directory "$var_addon_install_path" -f "$var_addon_compose_file" pull
  msg_ok "Pulled latest image"

  msg_info "Restarting ${APP}"
  $STD docker compose --project-directory "$var_addon_install_path" -f "$var_addon_compose_file" up -d --remove-orphans
  msg_ok "Restarted ${APP}"
  msg_ok "Updated successfully"
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"

  local teardown_state
  local -a teardown_inputs=("$var_addon_install_path" portainer "$var_addon_compose_file" /etc/systemd/system/portainer.service)
  addon_teardown_status teardown_state "${teardown_inputs[@]}" || return $?
  if [[ "$teardown_state" != 'done' ]]; then
    if [[ ! -f "$var_addon_compose_file" ]]; then
      msg_error "No ${APP} installation found (${var_addon_compose_file} missing); restore the selected manifest for scoped teardown"
      return 1
    fi
    addon_teardown_begin "${teardown_inputs[@]}" || return $?
    msg_info "Stopping and removing Docker containers"
    $STD docker compose --project-directory "$var_addon_install_path" -f "$var_addon_compose_file" down --volumes --remove-orphans
    addon_teardown_complete "${teardown_inputs[@]}" || return $?
    msg_ok "Stopped and removed Docker containers"
  fi

  svc_prepare_uninstall portainer
  addon_teardown_remove "${teardown_inputs[@]}" || return $?
  systemctl daemon-reload

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
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon_lxc") --script-id portainer -- "$@"
