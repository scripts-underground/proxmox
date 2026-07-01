#!/usr/bin/env bash

# community-scripts ORG | MQTTX Web Addon Installer
# Author: MickLesk
# License: MIT
# Source: https://github.com/emqx/MQTTX

REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="MQTTX Web"
# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP_TYPE="tools"
APP_DIR="/opt/mqttx"
SERVICE="mqttx-web"
REPO="emqx/MQTTX"
DEFAULT_PORT=8095

if ! grep -q -Ei 'debian|ubuntu' /etc/os-release; then
  msg_error "Unsupported OS. This addon supports only Debian or Ubuntu."
  exit 1
fi

IP=$(hostname -I | awk '{print $1}')

function is_installed() {
  [[ -d "$APP_DIR/web/dist" ]] && systemctl is-active --quiet "$SERVICE"
}

function install_script() {
  read -r -p "Enter port number (default: ${DEFAULT_PORT}): " PORT_INPUT
  PORT="${PORT_INPUT:-$DEFAULT_PORT}"
  read -r -p "Install ${APP}? (y/n): " answer
  answer="${answer//[[:space:]]/}"
  if [[ ! "${answer,,}" =~ ^(y|yes)$ ]]; then
    msg_info "Installation skipped"
    exit 0
  fi

  NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs

  fetch_and_deploy_gh_release "mqttx" "$REPO" "tarball" "latest" "$APP_DIR"

  msg_info "Building ${APP}"
  cd "$APP_DIR/web" || exit
  $STD yarn install --frozen-lockfile --ignore-engines
  $STD yarn build
  msg_ok "Built ${APP}"

  if ! dpkg -l nginx &> /dev/null; then
    msg_info "Installing Nginx"
    $STD apt install -y nginx
    msg_ok "Installed Nginx"
  fi

  msg_info "Configuring ${APP}"
  cat << EOF > /etc/nginx/sites-available/mqttx-web
server {
    listen ${PORT};

    root ${APP_DIR}/web/dist;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/mqttx-web /etc/nginx/sites-enabled/mqttx-web
  $STD nginx -t
  systemctl reload nginx

  cat << EOF > /etc/systemd/system/${SERVICE}.service
[Unit]
Description=${APP} (Nginx on port ${PORT})
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
  systemctl enable -q --now "$SERVICE"
}

function update_script() {
  if check_for_gh_release "mqttx" "$REPO"; then
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "mqttx" "$REPO" "tarball" "latest" "$APP_DIR"

    msg_info "Updating ${APP}"
    cd "$APP_DIR/web" || exit
    $STD yarn install --frozen-lockfile --ignore-engines
    $STD yarn build
    systemctl reload nginx
    msg_ok "${APP} updated"
  else
    msg_ok "${APP} is already up-to-date"
  fi
}

function uninstall_script() {
  msg_info "Removing ${APP}"
  systemctl disable -q --now "$SERVICE" 2> /dev/null || true
  rm -f "/etc/systemd/system/${SERVICE}.service"
  rm -f /etc/nginx/sites-enabled/mqttx-web
  rm -f /etc/nginx/sites-available/mqttx-web
  $STD nginx -t && systemctl reload nginx
  rm -rf "$APP_DIR"
  msg_ok "${APP} uninstalled"
}

function post_install_script() {
  msg_ok "${APP} installed at http://${IP}:${PORT}"
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon")

