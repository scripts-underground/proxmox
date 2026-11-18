#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: vhsdream
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/alangrainger/immich-public-proxy

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Immich Public Proxy"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_install_path="${var_addon_install_path:-/opt/immich-proxy}"
var_addon_config_path="${var_addon_config_path:-${var_addon_install_path}/app}"
var_addon_service_path="${var_addon_service_path:-/etc/systemd/system/immich-proxy.service}"
var_addon_backup_dir="${var_addon_backup_dir:-/opt/immich-public-proxy_backup}"
var_addon_default_port="${var_addon_default_port:-3000}"

function install_script() {
  if [[ "$OS_FAMILY" != "debian" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu only)"
    exit 1
  fi

  if command -v node &> /dev/null; then
    msg_ok "Node.js already installed ($(node -v))"
  else
    NODE_VERSION="24" setup_nodejs
  fi

  # Force fresh download by removing version cache
  rm -f "$HOME/.immichpublicproxy"
  fetch_and_deploy_gh_release "Immich Public Proxy" "alangrainger/immich-public-proxy" "tarball" "latest" "$var_addon_install_path"

  msg_info "Installing dependencies"
  cd "$var_addon_config_path" || exit
  $STD npm ci
  msg_ok "Installed dependencies"

  msg_info "Building ${APP}"
  $STD npm run build
  msg_ok "Built ${APP}"

  local MAX_ATTEMPTS=3
  local attempt=0
  DOMAIN=""
  while true; do
    attempt=$((attempt + 1))
    read -rp "${TAB3}Enter your LOCAL Immich IP or domain (ex. 192.168.1.100 or immich.local.lan): " DOMAIN || true
    if [[ -z "$DOMAIN" ]]; then
      if ((attempt >= MAX_ATTEMPTS)); then
        DOMAIN="${LOCAL_IP:-localhost}"
        msg_warn "Using fallback: $DOMAIN"
        break
      fi
      msg_warn "Domain cannot be empty! (Attempt $attempt/$MAX_ATTEMPTS)"
    elif [[ "$DOMAIN" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      local valid_ip=true
      local -a octets
      IFS='.' read -ra octets <<< "$DOMAIN"
      for octet in "${octets[@]}"; do
        if ((octet > 255)); then
          valid_ip=false
          break
        fi
      done
      if $valid_ip; then
        break
      else
        msg_warn "Invalid IP address!"
      fi
    elif [[ "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ || "$DOMAIN" == "localhost" ]]; then
      break
    else
      msg_warn "Invalid domain format!"
    fi
  done

  msg_info "Creating configuration"
  cat << EOF > "$var_addon_config_path/.env"
NODE_ENV=production
IMMICH_URL=http://${DOMAIN}:2283
EOF
  chmod 600 "$var_addon_config_path/.env"
  msg_ok "Created configuration"

  msg_info "Creating service"
  cat << EOF > "$var_addon_service_path"
[Unit]
Description=Immich Public Proxy
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${var_addon_install_path}/app
EnvironmentFile=${var_addon_config_path}/.env
ExecStart=/usr/bin/node ${var_addon_install_path}/app/dist/index.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now immich-proxy
  msg_ok "Created and started service"
}

function post_install_script() {
  echo ""
  msg_ok "${APP} is reachable at: ${BL}http://${LOCAL_IP}:${var_addon_default_port}${CL}"
  echo ""
  msg_warn "Additional configuration is available at '${var_addon_config_path}/config.json'"
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
}

function update_script() {
  if check_for_gh_release "Immich Public Proxy" "alangrainger/immich-public-proxy"; then
    local -a CLEAN_INSTALL_KEEP_PATHS=("${CLEAN_INSTALL_KEEP_PATHS[@]}")
    local config service was_running=0 update_status=0 before after
    for config in "$var_addon_config_path/.env" "$var_addon_config_path/config.json"; do
      case "$config" in
        "$var_addon_install_path"/*) CLEAN_INSTALL_KEEP_PATHS+=("${config#"$var_addon_install_path"/}") ;;
      esac
    done
    service=$(basename "$var_addon_service_path" .service)
    function immich_proxy_state() (
      set -o pipefail
      local path
      {
        printf '%s\0' "$var_addon_config_path/.env" || exit $?
        if [[ -e "$var_addon_config_path/config.json" || -L "$var_addon_config_path/config.json" ]]; then
          printf '%s\0' "$var_addon_config_path/config.json" || exit $?
        fi
        find "$var_addon_install_path/" -print0 || exit $?
      } | LC_ALL=C sort -zu | while IFS= read -r -d '' path; do
        printf '%s\0' "$path" || exit $?
        stat -c '%f:%u:%g' -- "$path" || exit $?
        if [[ -L "$path" ]]; then
          readlink -- "$path" || exit $?
          if [[ -f "$path" ]]; then sha256sum < "$path" || exit $?; fi
        elif [[ -f "$path" ]]; then
          sha256sum < "$path" || exit $?
        elif [[ ! -d "$path" ]]; then exit 65; fi
      done | sha256sum
    )
    before=$(immich_proxy_state) || return $?
    if systemctl is-active --quiet "$service"; then was_running=1; fi
    msg_info "Stopping service"
    systemctl stop "$service" || update_status=$?
    if [[ "$update_status" == 0 ]]; then
      msg_ok "Stopped service"
      (
        BACKUP_DIR="$var_addon_backup_dir" create_backup "$var_addon_config_path/.env" "$var_addon_config_path/config.json" || exit $?
        if command -v node &> /dev/null; then
          msg_ok "Node.js already installed ($(node -v))"
        else
          NODE_VERSION="24" setup_nodejs || exit $?
        fi
        CLEAN_INSTALL=1 fetch_and_deploy_gh_release "Immich Public Proxy" "alangrainger/immich-public-proxy" "tarball" "$CHECK_UPDATE_RELEASE" "$var_addon_install_path" || exit $?
        msg_info "Installing dependencies"
        cd "$var_addon_config_path" || exit $?
        $STD npm ci || exit $?
        msg_ok "Installed dependencies"
        msg_info "Building ${APP}"
        $STD npm run build || exit $?
        msg_ok "Built ${APP}"
      ) || update_status=$?
    fi
    if [[ "$update_status" != 0 ]]; then
      after=$(immich_proxy_state) || after=unverified
      if [[ "$after" == "$before" && "$was_running" == 1 ]]; then
        systemctl start "$service" || msg_warn "Unable to restart previous Immich Public Proxy service"
      elif [[ "$after" != "$before" ]]; then
        msg_warn "Previous Immich Public Proxy installation is unverified; service stays stopped"
      fi
      return "$update_status"
    fi
    if [[ "$was_running" == 1 ]]; then
      msg_info "Starting service"
      systemctl start "$service"
      msg_ok "Started service"
    fi
    msg_ok "Updated successfully"
  else
    local release_status=$?
    [[ "$release_status" == 1 ]] || return "$release_status"
  fi
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"
  svc_prepare_uninstall immich-proxy.service
  rm -f "$var_addon_service_path"
  rm -rf "$var_addon_install_path"
  rm -f "$HOME/.immichpublicproxy"
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
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon_lxc") --script-id immich-public-proxy -- "$@"
