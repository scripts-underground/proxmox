#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Andy Grunwald (andygrunwald)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/hansmi/prometheus-paperless-exporter

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="prometheus-paperless-ngx-exporter"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_bin_path="${var_addon_bin_path:-/usr/bin/prometheus-paperless-exporter}"
var_addon_conf_dir="${var_addon_conf_dir:-/etc/prometheus-paperless-ngx-exporter}"
var_addon_conf_path="${var_addon_conf_path:-${var_addon_conf_dir}/config.env}"
var_addon_auth_token_file="${var_addon_auth_token_file:-${var_addon_conf_dir}/paperless_auth_token_file}"
var_addon_service="${var_addon_service:-prometheus-paperless-ngx-exporter}"
var_addon_gh_repo="${var_addon_gh_repo:-hansmi/prometheus-paperless-exporter}"
var_addon_gh_app="${var_addon_gh_app:-prom-paperless-exp}"

function install_script() {
  if [[ "$OS_FAMILY" != "debian" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu only)"
    exit 1
  fi

  echo ""
  read -erp "${TAB}Enter URL of Paperless-NGX [http://127.0.0.1:8000]: " PAPERLESS_URL || true
  PAPERLESS_URL=${PAPERLESS_URL:-http://127.0.0.1:8000}

  read -rsp "${TAB}Enter Paperless-NGX authentication token: " PAPERLESS_AUTH_TOKEN || true
  echo ""
  if [[ -z "${PAPERLESS_AUTH_TOKEN:-}" ]]; then
    msg_error "An authentication token is required"
    exit 1
  fi

  fetch_and_deploy_gh_release "$var_addon_gh_app" "$var_addon_gh_repo" "binary" "latest"

  msg_info "Creating configuration"
  mkdir -p "$var_addon_conf_dir"
  cat << EOF > "$var_addon_conf_path"
# https://github.com/hansmi/prometheus-paperless-exporter
PAPERLESS_URL="${PAPERLESS_URL}"
EOF
  echo "${PAPERLESS_AUTH_TOKEN}" > "$var_addon_auth_token_file"
  chmod 600 "$var_addon_auth_token_file"
  msg_ok "Created configuration"

  msg_info "Creating service"
  cat << EOF > "/etc/systemd/system/${var_addon_service}.service"
[Unit]
Description=Prometheus Paperless NGX Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=root
EnvironmentFile=${var_addon_conf_path}
ExecStart=${var_addon_bin_path} \\
    --paperless_url=\${PAPERLESS_URL} \\
    --paperless_auth_token_file=${var_addon_auth_token_file} \\
    --paperless_header 'Accept: application/json; version=9' \\
    --collectors=tag,correspondent,document_type,storage_path,task,log,group,user,status,statistics
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
  echo -e "${INFO}${YW}Metrics:${CL} ${BGN}http://${LOCAL_IP}:8081/metrics${CL}"
  echo -e "${INFO}${YW}Config:${CL} ${var_addon_conf_path}"
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
}

function update_script() {
  if [[ ! -f "$var_addon_bin_path" ]]; then
    msg_error "${APP} is not installed"
    exit 233
  fi

  local release_found=1

  if check_for_gh_release "$var_addon_gh_app" "$var_addon_gh_repo"; then
    release_found=0
    msg_info "Stopping service"
    systemctl stop "$var_addon_service"
    msg_ok "Stopped service"

    fetch_and_deploy_gh_release "$var_addon_gh_app" "$var_addon_gh_repo" "binary" "latest"
  fi

  msg_info "Refreshing service configuration"
  cat << EOF > "/etc/systemd/system/${var_addon_service}.service"
[Unit]
Description=Prometheus Paperless NGX Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=root
EnvironmentFile=${var_addon_conf_path}
ExecStart=${var_addon_bin_path} \\
    --paperless_url=\${PAPERLESS_URL} \\
    --paperless_auth_token_file=${var_addon_auth_token_file} \\
    --paperless_header 'Accept: application/json; version=9' \\
    --collectors=tag,correspondent,document_type,storage_path,task,log,group,user,status,statistics
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  msg_ok "Refreshed service configuration"

  msg_info "Starting service"
  systemctl restart "$var_addon_service"
  msg_ok "Started service"

  if [[ $release_found -eq 0 ]]; then
    msg_ok "Updated successfully!"
  else
    msg_ok "No new release found, service configuration refreshed"
  fi
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"
  systemctl disable -q --now "$var_addon_service" || true

  if dpkg -l | grep -q prometheus-paperless-exporter; then
    $STD apt remove -y prometheus-paperless-exporter || $STD dpkg -r prometheus-paperless-exporter
  fi

  rm -f "/etc/systemd/system/${var_addon_service}.service"
  rm -rf "$var_addon_conf_dir"
  rm -f "$HOME/.prometheus-paperless-ngx-exporter"
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
