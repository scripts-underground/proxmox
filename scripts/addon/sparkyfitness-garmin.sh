#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Tom Frenzel (tomfrenzel)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/CodeWithCJ/SparkyFitness

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="SparkyFitness-Garmin"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_install_path="${var_addon_install_path:-/opt/sparkyfitness-garmin}"
var_addon_config_path="${var_addon_config_path:-/etc/sparkyfitness-garmin/.env}"
var_addon_service_path="${var_addon_service_path:-/etc/systemd/system/sparkyfitness-garmin.service}"
var_addon_default_port="${var_addon_default_port:-8000}"

function install_script() {
  if [[ "$OS_FAMILY" != "debian" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu only)"
    exit 1
  fi

  if [[ ! -d /opt/sparkyfitness ]]; then
    msg_error "No SparkyFitness installation detected. This addon must be installed within a container that already has SparkyFitness installed."
    exit 1
  fi

  PYTHON_VERSION="3.13" setup_uv
  fetch_and_deploy_gh_release "sparkyfitness-garmin" "CodeWithCJ/SparkyFitness" "tarball" "latest" "$var_addon_install_path"

  msg_info "Setting up ${APP}"
  mkdir -p "$(dirname "$var_addon_config_path")"
  cp "${var_addon_install_path}/docker/.env.example" "$var_addon_config_path"
  cd "${var_addon_install_path}/SparkyFitnessGarmin" || exit
  $STD uv venv --clear .venv
  $STD uv pip install -r requirements.txt
  sed -i -e "s|^#\?GARMIN_MICROSERVICE_URL=.*|GARMIN_MICROSERVICE_URL=http://${LOCAL_IP}:${var_addon_default_port}|" "$var_addon_config_path"
  cat << EOF > "$var_addon_service_path"
[Unit]
Description=${APP}
After=network.target sparkyfitness-server.service
Requires=sparkyfitness-server.service

[Service]
Type=simple
WorkingDirectory=${var_addon_install_path}/SparkyFitnessGarmin
EnvironmentFile=${var_addon_config_path}
ExecStart=${var_addon_install_path}/SparkyFitnessGarmin/.venv/bin/python3 -m uvicorn main:app --host 0.0.0.0 --port ${var_addon_default_port}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now sparkyfitness-garmin
  msg_ok "Set up ${APP}"
}

function post_install_script() {
  echo ""
  msg_ok "${APP} installed successfully"
  echo -e "${INFO}${YW}Web UI:${CL} ${BGN}http://${LOCAL_IP}:${var_addon_default_port}${CL}"
  echo -e "${INFO}${YW}Config:${CL} ${var_addon_config_path}"
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
  echo ""
  msg_warn "You might need to update the GARMIN_MICROSERVICE_URL in your SparkyFitness .env file to http://${LOCAL_IP}:${var_addon_default_port}"
}

function update_script() {
  if check_for_gh_release "sparkyfitness-garmin" "CodeWithCJ/SparkyFitness"; then
    PYTHON_VERSION="3.13" setup_uv

    msg_info "Stopping service"
    systemctl stop sparkyfitness-garmin.service &> /dev/null || true
    msg_ok "Stopped service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "sparkyfitness-garmin" "CodeWithCJ/SparkyFitness" "tarball" "latest" "$var_addon_install_path"
    cd "${var_addon_install_path}/SparkyFitnessGarmin" || exit
    $STD uv venv --clear .venv
    $STD uv pip install -r requirements.txt

    msg_info "Starting service"
    systemctl start sparkyfitness-garmin
    msg_ok "Started service"
    msg_ok "Updated successfully"
  fi
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"
  systemctl disable --now sparkyfitness-garmin.service &> /dev/null || true
  rm -rf "$var_addon_service_path" "$var_addon_config_path" "$var_addon_install_path" "$HOME/.sparkyfitness-garmin"
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
