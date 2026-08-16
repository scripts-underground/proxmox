#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/xperimental/nextcloud-exporter

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="nextcloud-exporter"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_bin_path="${var_addon_bin_path:-/usr/bin/nextcloud-exporter}"
var_addon_config_path="${var_addon_config_path:-/etc/nextcloud-exporter.env}"
var_addon_service="${var_addon_service:-nextcloud-exporter}"
var_addon_repo="${var_addon_repo:-xperimental/nextcloud-exporter}"
var_addon_default_port="${var_addon_default_port:-9205}"

function install_script() {
  if [[ "$OS_FAMILY" != "debian" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu only)"
    exit 1
  fi

  echo ""
  read -erp "${TAB}Enter URL of Nextcloud, example: (http://127.0.0.1:8080): " NEXTCLOUD_SERVER || true
  NEXTCLOUD_SERVER="${NEXTCLOUD_SERVER:-http://127.0.0.1:8080}"
  read -rsp "${TAB}Enter Nextcloud auth token (press Enter to use username/password instead): " NEXTCLOUD_AUTH_TOKEN || true
  echo ""

  if [[ -z "$NEXTCLOUD_AUTH_TOKEN" ]]; then
    read -erp "${TAB}Enter Nextcloud username: " NEXTCLOUD_USERNAME || true
    read -rsp "${TAB}Enter Nextcloud password: " NEXTCLOUD_PASSWORD || true
    echo ""
  fi

  read -erp "${TAB}Query additional info for apps? [Y/n]: " QUERY_APPS || true
  if [[ "${QUERY_APPS,,}" =~ ^(n|no)$ ]]; then
    NEXTCLOUD_INFO_APPS="false"
  fi

  read -erp "${TAB}Query update information? [Y/n]: " QUERY_UPDATES || true
  if [[ "${QUERY_UPDATES,,}" =~ ^(n|no)$ ]]; then
    NEXTCLOUD_INFO_UPDATE="false"
  fi

  read -erp "${TAB}Do you want to skip TLS-Verification (if using a self-signed Certificate on Nextcloud) [y/N]: " SKIP_TLS || true
  if [[ "${SKIP_TLS,,}" =~ ^(y|yes)$ ]]; then
    NEXTCLOUD_TLS_SKIP_VERIFY="true"
  fi

  fetch_and_deploy_gh_release "nextcloud-exporter" "$var_addon_repo" "binary" "latest"

  msg_info "Creating configuration"
  cat << EOF > "$var_addon_config_path"
# https://github.com/xperimental/nextcloud-exporter
NEXTCLOUD_SERVER="${NEXTCLOUD_SERVER}"
NEXTCLOUD_AUTH_TOKEN="${NEXTCLOUD_AUTH_TOKEN:-}"
NEXTCLOUD_USERNAME="${NEXTCLOUD_USERNAME:-}"
NEXTCLOUD_PASSWORD="${NEXTCLOUD_PASSWORD:-}"
NEXTCLOUD_INFO_UPDATE=${NEXTCLOUD_INFO_UPDATE:-"true"}
NEXTCLOUD_INFO_APPS=${NEXTCLOUD_INFO_APPS:-"true"}
NEXTCLOUD_TLS_SKIP_VERIFY=${NEXTCLOUD_TLS_SKIP_VERIFY:-"false"}
NEXTCLOUD_LISTEN_ADDRESS=":${var_addon_default_port}"
EOF
  msg_ok "Created configuration"

  msg_info "Creating service"
  cat << EOF > "/etc/systemd/system/${var_addon_service}.service"
[Unit]
Description=nextcloud-exporter
After=network.target

[Service]
User=root
EnvironmentFile=${var_addon_config_path}
ExecStart=${var_addon_bin_path}
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now "$var_addon_service"
  msg_ok "Created and started service"
}

function post_install_script() {
  echo ""
  msg_ok "${APP} installed successfully"
  echo -e "${INFO}${YW}Metrics:${CL} ${BGN}http://${LOCAL_IP}:${var_addon_default_port}/metrics${CL}"
  echo -e "${INFO}${YW}Config:${CL} ${var_addon_config_path}"
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
}

function update_script() {
  if [[ ! -f "$var_addon_bin_path" ]]; then
    msg_error "${APP} is not installed. Nothing to update."
    exit 233
  fi
  if check_for_gh_release "nextcloud-exporter" "$var_addon_repo"; then
    msg_info "Stopping service"
    systemctl stop "$var_addon_service"
    msg_ok "Stopped service"

    fetch_and_deploy_gh_release "nextcloud-exporter" "$var_addon_repo" "binary" "latest"

    msg_info "Starting service"
    systemctl start "$var_addon_service"
    msg_ok "Started service"
    msg_ok "Updated successfully!"
  fi
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"
  systemctl disable -q --now "$var_addon_service" &> /dev/null || true
  rm -f "/etc/systemd/system/${var_addon_service}.service"

  if dpkg -l | grep -q nextcloud-exporter; then
    $STD apt remove -y nextcloud-exporter || $STD dpkg -r nextcloud-exporter
  fi

  rm -f "$var_addon_config_path"
  rm -f "$HOME/.nextcloud-exporter"
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
