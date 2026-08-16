#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/sakowicz/actual-budget-prometheus-exporter

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="actual-budget-prometheus-exporter"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_install_path="${var_addon_install_path:-/opt/actual-budget-prometheus-exporter}"
var_addon_config_path="${var_addon_config_path:-/opt/actual-budget-prometheus-exporter.env}"
var_addon_service_path="${var_addon_service_path:-/etc/systemd/system/actual-budget-prometheus-exporter.service}"

function install_script() {
  if [[ "$OS_FAMILY" != "debian" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu only)"
    exit 1
  fi

  read -erp "Enter URL of Actual Budget server, example: (http://127.0.0.1:5006): " ACTUAL_SERVER_URL || true
  ACTUAL_SERVER_URL=${ACTUAL_SERVER_URL:-}
  read -rsp "Enter Actual Budget server password: " ACTUAL_PASSWORD || true
  ACTUAL_PASSWORD=${ACTUAL_PASSWORD:-}
  printf "\n"
  echo -e "${TAB}${INFO} Find the Sync ID in Actual under Settings > Advanced settings > Sync ID"
  read -erp "Enter Budget Sync ID: " ACTUAL_BUDGET_ID_1 || true
  ACTUAL_BUDGET_ID_1=${ACTUAL_BUDGET_ID_1:-}
  read -rsp "Enter E2E encryption password (leave empty if end-to-end encryption is disabled): " ACTUAL_E2E_PASSWORD_1 || true
  ACTUAL_E2E_PASSWORD_1=${ACTUAL_E2E_PASSWORD_1:-}
  printf "\n"
  read -erp "Enter metrics port (default: 3001): " PORT_INPUT || true
  PORT="${PORT_INPUT:-3001}"

  # build-essential and python3 are required to compile better-sqlite3
  # (native dependency of @actual-app/api) when no prebuilt binary is available.
  msg_info "Installing Dependencies"
  $STD apt install -y build-essential python3
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "actual-budget-prometheus-exporter" "sakowicz/actual-budget-prometheus-exporter" "tarball" "latest"
  NODE_VERSION="22" setup_nodejs

  msg_info "Building Actual-Budget-Prometheus-Exporter"
  cd "$var_addon_install_path" || exit
  $STD npm ci
  $STD npm run build
  msg_ok "Built Actual-Budget-Prometheus-Exporter"

  msg_info "Creating configuration"
  cat << EOF > "$var_addon_config_path"
# https://github.com/sakowicz/actual-budget-prometheus-exporter
ACTUAL_SERVER_URL="${ACTUAL_SERVER_URL}"
ACTUAL_PASSWORD="${ACTUAL_PASSWORD}"
ACTUAL_BUDGET_ID_1="${ACTUAL_BUDGET_ID_1}"
ACTUAL_E2E_PASSWORD_1="${ACTUAL_E2E_PASSWORD_1}"
PORT="${PORT}"
# Optional: friendly label for the budget shown in the exported metrics
# ACTUAL_BUDGET_NAME_1=""
# Optional: monitor additional budgets by incrementing the numeric suffix
# ACTUAL_BUDGET_ID_2=""
# ACTUAL_E2E_PASSWORD_2=""
# ACTUAL_BUDGET_NAME_2=""
# Optional: set to 0 to accept a self-signed TLS certificate on the Actual server
# NODE_TLS_REJECT_UNAUTHORIZED="0"
EOF
  msg_ok "Created configuration"

  msg_info "Creating service"
  cat << EOF > "$var_addon_service_path"
[Unit]
Description=Actual Budget Prometheus Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=root
WorkingDirectory=${var_addon_install_path}
EnvironmentFile=${var_addon_config_path}
ExecStart=/usr/bin/node ${var_addon_install_path}/dist/app.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now actual-budget-prometheus-exporter
  msg_ok "Created and started service"
}

function post_install_script() {
  echo ""
  msg_ok "Actual-Budget-Prometheus-Exporter installed successfully"
  echo -e "${INFO}${YW}Metrics:${CL} ${BGN}http://${LOCAL_IP}:${PORT}/metrics${CL}"
  echo -e "${INFO}${YW}Config:${CL} ${var_addon_config_path}"
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
}

function update_script() {
  if check_for_gh_release "actual-budget-prometheus-exporter" "sakowicz/actual-budget-prometheus-exporter"; then
    msg_info "Stopping service"
    systemctl stop actual-budget-prometheus-exporter
    msg_ok "Stopped service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "actual-budget-prometheus-exporter" "sakowicz/actual-budget-prometheus-exporter" "tarball" "latest"
    NODE_VERSION="22" setup_nodejs

    msg_info "Building Actual-Budget-Prometheus-Exporter"
    cd "$var_addon_install_path" || exit
    $STD npm ci
    $STD npm run build
    msg_ok "Built Actual-Budget-Prometheus-Exporter"

    msg_info "Starting service"
    systemctl start actual-budget-prometheus-exporter
    msg_ok "Started service"
    msg_ok "Updated successfully!"
  fi
  exit
}

function uninstall_script() {
  msg_info "Uninstalling Actual-Budget-Prometheus-Exporter"
  systemctl disable -q --now actual-budget-prometheus-exporter
  rm -f "$var_addon_service_path"
  rm -rf "$var_addon_install_path"
  rm -f "$var_addon_config_path"
  rm -f "$HOME/.actual-budget-prometheus-exporter"
  msg_ok "Actual-Budget-Prometheus-Exporter has been uninstalled"
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
