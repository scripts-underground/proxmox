#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/martabal/qbittorrent-exporter

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="qbittorrent-exporter"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_install_path="${var_addon_install_path:-/opt/qbittorrent-exporter}"
var_addon_config_path="${var_addon_config_path:-/opt/qbittorrent-exporter.env}"
var_addon_service="${var_addon_service:-qbittorrent-exporter}"
var_addon_repo="${var_addon_repo:-martabal/qbittorrent-exporter}"
var_addon_default_port="${var_addon_default_port:-8090}"

function install_script() {
  if [[ "$OS_FAMILY" != "debian" && "$OS_FAMILY" != "alpine" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu and Alpine only)"
    exit 1
  fi

  echo ""
  read -erp "${TAB3}Enter URL of qBittorrent, example: (http://127.0.0.1:8080): " QBITTORRENT_BASE_URL || true
  echo -e "${TAB3}${INFO} Create an API key in qBittorrent under Tools > Options > Web UI > API key"
  read -erp "${TAB3}Enter qBittorrent API key: " QBITTORRENT_API_KEY || true

  fetch_and_deploy_gh_release "qbittorrent-exporter" "$var_addon_repo" "tarball" "latest" "$var_addon_install_path"
  setup_go

  msg_info "Building qBittorrent-Exporter"
  cd "$var_addon_install_path" || exit
  $STD /usr/local/bin/go build -o ./qbittorrent-exporter
  msg_ok "Built qBittorrent-Exporter"

  msg_info "Creating configuration"
  cat << EOF > "$var_addon_config_path"
# https://github.com/martabal/qbittorrent-exporter?tab=readme-ov-file#parameters
QBITTORRENT_BASE_URL="${QBITTORRENT_BASE_URL:-http://127.0.0.1:8080}"
QBITTORRENT_API_KEY="${QBITTORRENT_API_KEY:-}"
EOF
  chmod 600 "$var_addon_config_path"
  msg_ok "Created configuration"

  msg_info "Creating service"
  if [[ "$INIT_SYSTEM" == "openrc" ]]; then
    cat << EOF > "/etc/init.d/${var_addon_service}"
#!/sbin/openrc-run

name="qbittorrent-exporter"
description="qBittorrent Exporter for Prometheus"
command="${var_addon_install_path}/qbittorrent-exporter"
command_background=true
directory="${var_addon_install_path}"
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/qbittorrent-exporter.log"
error_log="/var/log/qbittorrent-exporter.log"

depend() {
    need net
    after firewall
}

start_pre() {
    if [ -f "${var_addon_config_path}" ]; then
        export \$(grep -v '^#' ${var_addon_config_path} | xargs)
    fi
}
EOF
    chmod +x "/etc/init.d/${var_addon_service}"
    $STD rc-update add "$var_addon_service" default
    $STD rc-service "$var_addon_service" start
  else
    cat << EOF > "/etc/systemd/system/${var_addon_service}.service"
[Unit]
Description=qbittorrent-exporter
After=network.target

[Service]
User=root
WorkingDirectory=${var_addon_install_path}
EnvironmentFile=${var_addon_config_path}
ExecStart=${var_addon_install_path}/qbittorrent-exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable -q --now "$var_addon_service"
  fi
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
  if [[ ! -f "${var_addon_install_path}/qbittorrent-exporter" ]]; then
    msg_error "${APP} is not installed. Nothing to update."
    exit 233
  fi
  if check_for_gh_release "qbittorrent-exporter" "$var_addon_repo"; then
    # Upstream v2 retains legacy authentication. Preserve the operator's login
    # method rather than forcing a credential migration unrelated to the server.
    local was_running=0 update_status=0 before after
    function qbittorrent_exporter_state() (
      local -a inputs=(--file "$var_addon_config_path")
      [[ "$INIT_SYSTEM" != openrc ]] || inputs=(--optional "$var_addon_config_path")
      addon_runtime_fingerprint --tree "$var_addon_install_path" "${inputs[@]}" --unit "$var_addon_service"
    )
    before=$(qbittorrent_exporter_state) || before=unverified
    addon_service_begin "$var_addon_service" was_running || return $?
    msg_info "Stopping service"
    if [[ "$INIT_SYSTEM" == "openrc" ]]; then
      rc-service "$var_addon_service" stop || update_status=$?
    else
      systemctl stop "$var_addon_service" || update_status=$?
    fi
    if [[ "$update_status" == 0 ]]; then
      msg_ok "Stopped service"
      (
        fetch_and_deploy_gh_release "qbittorrent-exporter" "$var_addon_repo" "tarball" "$CHECK_UPDATE_RELEASE" "$var_addon_install_path" || exit $?
        setup_go || exit $?
        msg_info "Building qBittorrent-Exporter"
        cd "$var_addon_install_path" || exit $?
        $STD /usr/local/bin/go build -o ./qbittorrent-exporter || exit $?
        msg_ok "Built qBittorrent-Exporter"
      ) || update_status=$?
    fi
    if [[ "$update_status" != 0 ]]; then
      after=$(qbittorrent_exporter_state) || after=unverified
      if [[ "$before" != unverified && "$after" == "$before" && "$was_running" == 1 ]]; then
        if [[ "$INIT_SYSTEM" == openrc ]]; then
          rc-service "$var_addon_service" start || msg_warn "Unable to restart previous qBittorrent exporter"
        else
          systemctl start "$var_addon_service" || msg_warn "Unable to restart previous qBittorrent exporter"
        fi
      elif [[ "$after" != "$before" ]]; then
        msg_warn "Previous qBittorrent exporter is unverified; service stays stopped"
      fi
      return "$update_status"
    fi
    if [[ "$was_running" == 1 ]]; then
      msg_info "Starting service"
      addon_service_complete "$var_addon_service" || return $?
      msg_ok "Started service"
    fi
    msg_ok "Updated successfully!"
  else
    local release_status=$?
    [[ "$release_status" == 1 ]] || return "$release_status"
  fi
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"
  svc_prepare_uninstall "$var_addon_service"
  if [[ "$INIT_SYSTEM" == "openrc" ]]; then
    rm -f "/etc/init.d/${var_addon_service}"
  else
    rm -f "/etc/systemd/system/${var_addon_service}.service"
  fi
  rm -rf "$var_addon_install_path"
  rm -f "$var_addon_config_path"
  rm -f "$HOME/.qbittorrent-exporter"
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
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon_lxc") --script-id qbittorrent-exporter -- "$@"
