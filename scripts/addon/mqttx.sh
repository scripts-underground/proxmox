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
  local site_stage site_marker site_probe enabled_identity='' nginx_status=0
  local available=/etc/nginx/sites-available/mqttx-web enabled=/etc/nginx/sites-enabled/mqttx-web
  site_stage=$(mktemp -d /etc/nginx/sites-available/.mqttx-install.XXXXXXXX) || return $?
  site_marker="mqttx-web-${site_stage##*.}"
  site_probe="/.su-${site_marker}"
  cat << EOF > "$site_stage/available"
server {
    listen ${MQTTX_PORT};

    root ${var_addon_app_dir}/web/dist;
    index index.html;

    location = ${site_probe} {
        default_type text/plain;
        return 200 "${site_marker}";
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
  cp -p -- "$site_stage/available" "$site_stage/expected" || nginx_status=$?
  if [[ "$nginx_status" == 0 ]]; then ln -- "$site_stage/available" "$available" || nginx_status=$?; fi
  if [[ "$nginx_status" == 0 ]]; then ln -s -- "$available" "$enabled" || nginx_status=$?; fi
  if [[ "$nginx_status" == 0 ]]; then enabled_identity=$(stat -c '%d:%i' -- "$enabled") || nginx_status=$?; fi
  if [[ "$nginx_status" == 0 ]]; then $STD nginx -t || nginx_status=$?; fi
  if [[ "$nginx_status" == 0 ]]; then systemctl reload nginx || nginx_status=$?; fi
  if [[ "$nginx_status" == 0 ]]; then
    local listener_attempt listener_response listener_accepted=0
    for ((listener_attempt = 0; listener_attempt < 30; listener_attempt++)); do
      if listener_response=$(curl --noproxy '*' --fail --silent --show-error --max-time 1 "http://127.0.0.1:${MQTTX_PORT}${site_probe}" 2> /dev/null) &&
        [[ "$listener_response" == "$site_marker" ]]; then
        listener_accepted=1
        break
      fi
      sleep 0.2
    done
    [[ "$listener_accepted" == 1 ]] || nginx_status=69
  fi
  if [[ "$nginx_status" != 0 ]]; then
    # Only this preparation's exact files may be removed. A concurrent writer
    # leaves an actionable recovery stage rather than receiving blind deletion.
    if [[ -e "$available" || -L "$available" ]]; then
      if [[ -L "$available" || ! "$available" -ef "$site_stage/available" ]] || ! cmp -s -- "$available" "$site_stage/expected"; then
        msg_error "MQTTX site changed; recovery retained at ${site_stage}"
        return "$nginx_status"
      fi
    fi
    if [[ -e "$enabled" || -L "$enabled" ]]; then
      if [[ ! -L "$enabled" || -z "$enabled_identity" || "$(stat -c '%d:%i' -- "$enabled")" != "$enabled_identity" || "$(readlink -- "$enabled")" != "$available" ]]; then
        msg_error "MQTTX enabled link changed; recovery retained at ${site_stage}"
        return "$nginx_status"
      fi
      rm -f -- "$enabled" || {
        msg_error "MQTTX rollback failed; recovery retained at ${site_stage}"
        return "$nginx_status"
      }
    fi
    rm -f -- "$available" || {
      msg_error "MQTTX rollback failed; recovery retained at ${site_stage}"
      return "$nginx_status"
    }
    if $STD nginx -t; then
      systemctl reload nginx || msg_error "Nginx reload of the restored configuration failed"
    else msg_error "Nginx validation of the restored configuration failed"; fi
    rm -f -- "$site_stage/available" "$site_stage/expected" || msg_error "MQTTX preparation retained at ${site_stage}"
    rmdir -- "$site_stage" || msg_error "MQTTX preparation retained at ${site_stage}"
    msg_error "Nginx did not accept the new MQTTX site; installation failed"
    return "$nginx_status"
  fi
  rm -f -- "$site_stage/available" "$site_stage/expected"
  rmdir -- "$site_stage"
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
  local site_stage="" uninstall_status=0 reload_attempted=0 app_was_running=no
  if [[ -e "$enabled" || -L "$enabled" ]]; then
    if [[ ! -L "$enabled" || "$(readlink -- "$enabled")" != "$available" ]]; then
      msg_error "Nginx site ${enabled} is not the addon-created link; retaining it"
      return 65
    fi
  fi
  if [[ -e "$available" || -L "$available" ]]; then
    [[ -f "$available" && ! -L "$available" ]] || {
      msg_error "Nginx site ${available} is not a regular addon configuration"
      return 65
    }
  fi
  site_stage=$(mktemp -d /etc/nginx/sites-available/.mqttx-uninstall.XXXXXXXX) || return $?
  if [[ -e "$enabled" || -L "$enabled" ]]; then mv -T -- "$enabled" "$site_stage/enabled" || uninstall_status=$?; fi
  if [[ "$uninstall_status" == 0 && -e "$available" ]]; then mv -T -- "$available" "$site_stage/available" || uninstall_status=$?; fi
  if [[ "$uninstall_status" == 0 ]]; then $STD nginx -t || uninstall_status=$?; fi
  if [[ "$uninstall_status" == 0 ]]; then
    reload_attempted=1
    systemctl reload nginx || uninstall_status=$?
  fi
  if [[ "$uninstall_status" == 0 ]]; then svc_prepare_uninstall "$var_addon_service" disable app_was_running || uninstall_status=$?; fi
  if [[ "$uninstall_status" != 0 ]]; then
    # Stage BOTH names before validation: a second foreign enabled link must
    # expose its dangling target to nginx -t, not break after successful teardown.
    local site_part site_dest
    for site_part in available enabled; do
      site_dest=$available
      [[ "$site_part" != enabled ]] || site_dest=$enabled
      if [[ -e "$site_stage/$site_part" || -L "$site_stage/$site_part" ]]; then
        if [[ -e "$site_dest" || -L "$site_dest" ]] || ! mv -nT -- "$site_stage/$site_part" "$site_dest" || [[ -e "$site_stage/$site_part" || -L "$site_stage/$site_part" ]]; then
          msg_error "Could not restore ${site_dest}; recovery retained at ${site_stage}"
          return "$uninstall_status"
        fi
      fi
    done
    if [[ "$reload_attempted" == 1 ]]; then
      if $STD nginx -t; then
        systemctl reload nginx || msg_error "Nginx reload of the restored site failed"
      else msg_error "Nginx validation of the restored site failed"; fi
    fi
    if [[ "$app_was_running" == yes ]]; then svc_start "$var_addon_service" || msg_error "MQTTX app activation recovery failed"; fi
    if [[ -n "$site_stage" ]]; then rmdir -- "$site_stage" || msg_error "Could not remove empty recovery stage ${site_stage}"; fi
    return "$uninstall_status"
  fi
  rm -f "/etc/systemd/system/${var_addon_service}.service"
  if [[ -n "$site_stage" ]]; then
    rm -f -- "$site_stage/enabled" "$site_stage/available"
    rmdir -- "$site_stage"
  fi
  rm -rf "$var_addon_app_dir"
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
