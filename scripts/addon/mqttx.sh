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
  $STD nginx -t
  systemctl reload nginx
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
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "mqttx" "$var_addon_repo" "tarball" "latest" "$var_addon_app_dir"

    msg_info "Updating ${APP}"
    cd "$var_addon_app_dir/web" || exit
    $STD yarn install --frozen-lockfile --ignore-engines
    $STD yarn build
    systemctl reload nginx
    msg_ok "Updated ${APP}"
  fi
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"
  systemctl disable -q --now "$var_addon_service" 2> /dev/null || true
  rm -f "/etc/systemd/system/${var_addon_service}.service"
  rm -f /etc/nginx/sites-enabled/mqttx-web
  rm -f /etc/nginx/sites-available/mqttx-web
  if command -v nginx &> /dev/null; then
    $STD nginx -t && systemctl reload nginx
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
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon_lxc")
