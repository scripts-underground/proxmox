#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/bakito/adguardhome-sync

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="AdGuardHome-Sync"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_install_path="${var_addon_install_path:-/opt/adguardhome-sync}"
var_addon_config_path="${var_addon_config_path:-/opt/adguardhome-sync/adguardhome-sync.yaml}"
var_addon_backup_dir="${var_addon_backup_dir:-/opt/adguardhome-sync_backup}"
var_addon_service="${var_addon_service:-adguardhome-sync}"
var_addon_repo="${var_addon_repo:-bakito/adguardhome-sync}"
var_addon_default_port="${var_addon_default_port:-8080}"

function install_script() {
  if [[ "$OS_FAMILY" != "debian" && "$OS_FAMILY" != "alpine" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu and Alpine only)"
    exit 1
  fi

  fetch_and_deploy_gh_release "adguardhome-sync" "$var_addon_repo" "prebuild" "latest" "$var_addon_install_path" "adguardhome-sync_*_linux_$(get_system_arch uname).tar.gz"

  # Gather configuration from user
  echo ""
  echo -e "${TAB}Enter details for your AdGuard Home instances."
  echo -e "${TAB}The Origin is your primary instance, Replica will sync from it."
  echo ""

  # Origin instance
  echo -e "${YW}── Origin (Primary) Instance ──${CL}"
  local origin_url origin_user origin_pass
  read -erp "  Origin URL (e.g., http://192.168.1.1): " origin_url || true
  origin_url="${origin_url:-http://192.168.1.1}"
  # Add http:// if no protocol specified
  [[ ! "$origin_url" =~ ^https?:// ]] && origin_url="http://${origin_url}"
  read -erp "  Origin Username [admin]: " origin_user || true
  origin_user="${origin_user:-admin}"
  read -rsp "  Origin Password: " origin_pass || true
  echo ""
  origin_pass="${origin_pass:-changeme}"

  # Replica instance
  echo ""
  echo -e "${YW}── Replica Instance ──${CL}"
  local replica_url replica_user replica_pass
  read -erp "  Replica URL (e.g., http://192.168.1.2): " replica_url || true
  replica_url="${replica_url:-http://192.168.1.2}"
  # Add http:// if no protocol specified
  [[ ! "$replica_url" =~ ^https?:// ]] && replica_url="http://${replica_url}"
  read -erp "  Replica Username [admin]: " replica_user || true
  replica_user="${replica_user:-admin}"
  read -rsp "  Replica Password: " replica_pass || true
  echo ""
  replica_pass="${replica_pass:-changeme}"
  echo ""

  msg_info "Creating configuration"
  cat << EOF > "$var_addon_config_path"
# AdGuardHome-Sync Configuration
# Documentation: https://github.com/bakito/adguardhome-sync

# Cron expression for sync interval (e.g., every 2 hours: "0 */2 * * *")
cron: "0 */2 * * *"

# Run sync on startup
runOnStart: true

# Continue sync on errors
continueOnError: false

# Origin AdGuardHome instance (primary)
origin:
  url: "${origin_url}"
  username: "${origin_user}"
  password: "${origin_pass}"
  insecureSkipVerify: false

# Replica instances (one or more)
replicas:
  - url: "${replica_url}"
    username: "${replica_user}"
    password: "${replica_pass}"
    insecureSkipVerify: false
  # Add more replicas as needed:
  # - url: "http://192.168.1.3"
  #   username: "admin"
  #   password: "changeme"

# API settings (web UI)
api:
  port: ${var_addon_default_port}
  darkMode: true
  metrics:
    enabled: false

# Sync features (all enabled by default)
features:
  dns:
    accessLists: true
    serverConfig: true
    rewrites: true
  dhcp:
    serverConfig: true
    staticLeases: true
  generalSettings: true
  queryLogConfig: true
  statsConfig: true
  clientSettings: true
  services: true
  filters: true
  theme: true
EOF
  chmod 600 "$var_addon_config_path"
  msg_ok "Created configuration"

  msg_info "Creating service"
  if [[ "$INIT_SYSTEM" == "openrc" ]]; then
    cat << EOF > "/etc/init.d/${var_addon_service}"
#!/sbin/openrc-run

name="adguardhome-sync"
description="AdGuardHome Sync"
command="${var_addon_install_path}/adguardhome-sync"
command_args="run --config ${var_addon_config_path}"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/adguardhome-sync.log"
error_log="/var/log/adguardhome-sync.log"

depend() {
    need net
    after firewall
}
EOF
    chmod +x "/etc/init.d/${var_addon_service}"
    rc-update add "$var_addon_service" default
    rc-service "$var_addon_service" start
  else
    cat << EOF > "/etc/systemd/system/${var_addon_service}.service"
[Unit]
Description=AdGuardHome Sync
After=network.target

[Service]
Type=simple
ExecStart=${var_addon_install_path}/adguardhome-sync run --config ${var_addon_config_path}
Restart=always
RestartSec=10

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
  echo -e "${INFO}${YW}Web UI:${CL} ${BGN}http://${LOCAL_IP}:${var_addon_default_port}${CL}"
  echo -e "${INFO}${YW}Config:${CL} ${var_addon_config_path}"
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
  echo ""
  msg_warn "Edit the config file to add your AdGuardHome instances!"
  msg_warn "  Origin: Your primary AdGuardHome instance"
  msg_warn "  Replicas: One or more replica instances to sync to"
}

function update_script() {
  if [[ ! -f "${var_addon_install_path}/adguardhome-sync" ]]; then
    msg_error "${APP} is not installed. Nothing to update."
    exit 233
  fi
  if check_for_gh_release "adguardhome-sync" "$var_addon_repo"; then
    msg_info "Stopping service"
    if [[ "$INIT_SYSTEM" == "openrc" ]]; then
      rc-service "$var_addon_service" stop &> /dev/null || true
    else
      systemctl stop "$var_addon_service" &> /dev/null || true
    fi
    msg_ok "Stopped service"

    BACKUP_DIR="$var_addon_backup_dir" create_backup "$var_addon_config_path"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "adguardhome-sync" "$var_addon_repo" "prebuild" "latest" "$var_addon_install_path" "adguardhome-sync_*_linux_$(get_system_arch uname).tar.gz"

    BACKUP_DIR="$var_addon_backup_dir" restore_backup

    msg_info "Starting service"
    if [[ "$INIT_SYSTEM" == "openrc" ]]; then
      rc-service "$var_addon_service" start
    else
      systemctl start "$var_addon_service"
    fi
    msg_ok "Started service"
    msg_ok "Updated successfully!"
  fi
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"
  if [[ "$INIT_SYSTEM" == "openrc" ]]; then
    rc-service "$var_addon_service" stop &> /dev/null || true
    rc-update del "$var_addon_service" &> /dev/null || true
    rm -f "/etc/init.d/${var_addon_service}"
  else
    systemctl disable --now "$var_addon_service" &> /dev/null || true
    rm -f "/etc/systemd/system/${var_addon_service}.service"
  fi
  rm -rf "$var_addon_install_path"
  rm -f "$HOME/.adguardhome-sync"
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
