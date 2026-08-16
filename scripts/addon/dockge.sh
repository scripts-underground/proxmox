#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster) | Addon: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://dockge.kuma.pet/ | Github: https://github.com/louislam/dockge

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Dockge"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_install_path="${var_addon_install_path:-/opt/dockge}"
var_addon_stacks_path="${var_addon_stacks_path:-/opt/stacks}"
var_addon_compose_url="${var_addon_compose_url:-https://raw.githubusercontent.com/louislam/dockge/master/compose.yaml}"
var_addon_default_port="${var_addon_default_port:-5001}"

function install_script() {
  if [[ "$OS_FAMILY" != "debian" && "$OS_FAMILY" != "alpine" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu and Alpine only)"
    exit 1
  fi

  # Dockge drives the Docker socket — Docker is a hard dependency and is
  # installed transparently when missing (official Docker repo, matching
  # upstream; set USE_DOCKER_REPO=false for distro packages)
  if ! command -v docker &> /dev/null; then
    if [[ "$OS_FAMILY" == "alpine" ]]; then
      msg_info "Installing Docker"
      $STD apk add --no-cache docker docker-cli-compose
      $STD rc-update add docker default
      $STD rc-service docker start
      msg_ok "Installed Docker"
    else
      USE_DOCKER_REPO="${USE_DOCKER_REPO:-true}" setup_docker || {
        msg_error "Docker installation failed"
        exit 1
      }
    fi
  fi
  if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
    msg_error "Docker or the Compose plugin is unavailable — install docker-ce + docker-compose-plugin and re-run"
    exit 1
  fi

  msg_info "Creating install directories"
  mkdir -p "$var_addon_install_path" "$var_addon_stacks_path"
  msg_ok "Created ${var_addon_install_path} and ${var_addon_stacks_path}"

  msg_info "Downloading Docker Compose file"
  curl -fsSL "$var_addon_compose_url" -o "${var_addon_install_path}/compose.yaml"
  msg_ok "Downloaded Docker Compose file"

  if [[ "$INIT_SYSTEM" == "systemd" ]]; then
    msg_info "Creating Service"
    cat << EOF > /etc/systemd/system/dockge.service
[Unit]
Description=Dockge - self-hosted Docker Compose stack manager
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${var_addon_install_path}
ExecStart=/usr/bin/docker compose up -d --remove-orphans
ExecStop=/usr/bin/docker compose down --remove-orphans
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable -q dockge
    msg_ok "Created Service"
  fi

  msg_info "Starting ${APP}"
  if [[ "$INIT_SYSTEM" == "systemd" ]]; then
    systemctl start dockge
  else
    cd "$var_addon_install_path" || exit 1
    $STD docker compose up -d
  fi
  msg_ok "Started ${APP}"
}

function post_install_script() {
  echo ""
  msg_ok "${APP} installed successfully"
  echo -e "${INFO}${YW}Web UI:${CL} ${BGN}http://${LOCAL_IP}:${var_addon_default_port}${CL}"
  echo -e "${INFO}${YW}Stacks:${CL} ${var_addon_stacks_path}"
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
}

function update_script() {
  if [[ ! -f "${var_addon_install_path}/compose.yaml" ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Pulling latest ${APP} image"
  cd "$var_addon_install_path" || exit 1
  $STD docker compose pull
  msg_ok "Pulled latest image"

  msg_info "Restarting ${APP}"
  $STD docker compose up -d --remove-orphans
  msg_ok "Restarted ${APP}"

  msg_ok "Updated successfully!"
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"

  if [[ -f "${var_addon_install_path}/compose.yaml" ]]; then
    msg_info "Stopping and removing Docker containers"
    cd "$var_addon_install_path" || return 1
    $STD docker compose down --remove-orphans
    msg_ok "Stopped and removed Docker containers"
  fi

  if [[ "$INIT_SYSTEM" == "systemd" ]]; then
    systemctl disable --now dockge &> /dev/null || true
    rm -f /etc/systemd/system/dockge.service
  fi

  rm -rf "$var_addon_install_path"
  msg_ok "${APP} has been uninstalled"
  msg_warn "Stacks directory ${var_addon_stacks_path} was NOT removed. Delete manually if no longer needed."
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
