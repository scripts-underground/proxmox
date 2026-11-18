#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2026 scripts-underground.org
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/emqx/MQTTX

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="MQTTX Web"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_app_dir="${var_addon_app_dir:-/opt/mqttx}"
var_addon_service="${var_addon_service:-mqttx-web}"
var_addon_repo="${var_addon_repo:-emqx/MQTTX}"
var_addon_default_port="${var_addon_default_port:-8095}"

function install_script() {
  [[ "$OS_FAMILY" == "debian" ]] || {
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu only)"
    exit 1
  }

  # An existing CT can already own these names without an addon marker.
  local site_path
  for site_path in /etc/nginx/sites-available/mqttx-web /etc/nginx/sites-enabled/mqttx-web; do
    if [[ -e "$site_path" || -L "$site_path" ]]; then
      msg_error "Existing Nginx site ${site_path}; retaining it without installation"
      return 65
    fi
  done

  echo ""
  read -erp "${TAB}Enter port for ${APP} [${var_addon_default_port}]: " MQTTX_PORT || true
  MQTTX_PORT=${MQTTX_PORT:-$var_addon_default_port}

  NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs

  fetch_and_deploy_gh_release "mqttx" "$var_addon_repo" "tarball" "latest" "$var_addon_app_dir"

  msg_info "Building ${APP}"
  cd "$var_addon_app_dir/web" || exit
  $STD yarn install --frozen-lockfile --ignore-engines
  $STD yarn build
  msg_ok "Built ${APP}"

  if ! dpkg -l nginx &> /dev/null; then
    msg_info "Installing Nginx"
    $STD apt install -y nginx
    msg_ok "Installed Nginx"
  fi

  msg_info "Configuring Nginx"
  cat << EOF > /etc/nginx/sites-available/mqttx-web
server {
    listen ${MQTTX_PORT};

    root ${var_addon_app_dir}/web/dist;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/mqttx-web /etc/nginx/sites-enabled/mqttx-web
  local nginx_status=0
  $STD nginx -t || nginx_status=$?
  if [[ "$nginx_status" == 0 ]]; then systemctl reload nginx || nginx_status=$?; fi
  if [[ "$nginx_status" != 0 ]]; then
    rm -f /etc/nginx/sites-enabled/mqttx-web /etc/nginx/sites-available/mqttx-web
    msg_error "Nginx did not accept the new MQTTX site; installation failed"
    return "$nginx_status"
  fi
  msg_ok "Configured Nginx"

  msg_info "Creating Service"
  cat << EOF > "/etc/systemd/system/${var_addon_service}.service"
[Unit]
Description=${APP} (Nginx on port ${MQTTX_PORT})
After=network.target
BindsTo=nginx.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
ExecReload=/usr/sbin/nginx -s reload

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now "$var_addon_service"
  msg_ok "Created Service"
}

function post_install_script() {
  echo ""
  msg_ok "${APP} installed successfully"
  echo -e "${INFO}${YW}Web UI:${CL} ${BGN}http://${LOCAL_IP}:${MQTTX_PORT}${CL}"
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
}

function update_script() {
  if check_for_gh_release "mqttx" "$var_addon_repo"; then
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "mqttx" "$var_addon_repo" "tarball" "$CHECK_UPDATE_RELEASE" "$var_addon_app_dir"

    msg_info "Updating ${APP}"
    cd "$var_addon_app_dir/web" || exit
    $STD yarn install --frozen-lockfile --ignore-engines
    $STD yarn build
    systemctl reload nginx
    msg_ok "Updated ${APP}"
  else
    local release_status=$?
    [[ "$release_status" == 1 ]] || return "$release_status"
  fi
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"
  command -v nginx &> /dev/null || {
    msg_error "Nginx is unavailable; retaining MQTTX"
    return 69
  }
  local enabled=/etc/nginx/sites-enabled/mqttx-web available=/etc/nginx/sites-available/mqttx-web
  local site_stage="" uninstall_status=0 reload_attempted=0
  if [[ -e "$enabled" || -L "$enabled" ]]; then
    if [[ ! -L "$enabled" || "$(readlink -- "$enabled")" != "$available" ]]; then
      msg_error "Nginx site ${enabled} is not the addon-created link; retaining it"
      return 65
    fi
    site_stage=$(mktemp -d /etc/nginx/sites-available/.mqttx-uninstall.XXXXXXXX) || return $?
    mv -T -- "$enabled" "$site_stage/enabled" || uninstall_status=$?
  fi
  if [[ "$uninstall_status" == 0 ]]; then $STD nginx -t || uninstall_status=$?; fi
  if [[ "$uninstall_status" == 0 ]]; then
    reload_attempted=1
    systemctl reload nginx || uninstall_status=$?
  fi
  if [[ "$uninstall_status" == 0 ]]; then svc_prepare_uninstall "$var_addon_service" || uninstall_status=$?; fi
  if [[ "$uninstall_status" != 0 ]]; then
    # Keep the available configuration and app/unit until shared Nginx accepts
    # removal. Restore the exact enabled link, never clobber a competing writer.
    if [[ -n "$site_stage" && -L "$site_stage/enabled" ]]; then
      if [[ -e "$enabled" || -L "$enabled" ]] || ! mv -nT -- "$site_stage/enabled" "$enabled" || [[ -L "$site_stage/enabled" ]]; then
        msg_error "Could not restore ${enabled}; recovery link retained at ${site_stage}/enabled"
        return "$uninstall_status"
      fi
      if [[ "$reload_attempted" == 1 ]]; then
        if $STD nginx -t; then systemctl reload nginx || msg_error "Nginx reload of the restored site failed"; fi
      fi
    fi
    if [[ -n "$site_stage" ]]; then rmdir -- "$site_stage" || msg_error "Could not remove empty recovery stage ${site_stage}"; fi
    return "$uninstall_status"
  fi
  rm -f "/etc/systemd/system/${var_addon_service}.service" "$available"
  if [[ -n "$site_stage" ]]; then
    rm -f -- "$site_stage/enabled"
    rmdir -- "$site_stage"
  fi
  rm -rf "$var_addon_app_dir"
  rm -f "$HOME/.mqttx"
  msg_ok "${APP} uninstalled"
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
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon_lxc") --script-id mqttx -- "$@"
