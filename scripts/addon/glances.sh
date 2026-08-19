#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster) | MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://nicolargo.github.io/glances/ | Github: https://github.com/nicolargo/glances

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Glances"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_app_dir="${var_addon_app_dir:-/opt/glances}"
var_addon_service="${var_addon_service:-glances}"

function header_info() {
  clear
  cat << "EOF"
   ________
  / ____/ /___ _____  ________  _____
 / / __/ / __ `/ __ \/ ___/ _ \/ ___/
/ /_/ / / /_/ / / / / /__/  __(__  )
\____/_/\__,_/_/ /_/\___/\___/____/

EOF
}

function install_script() {
  msg_info "Installing dependencies"
  if [[ "$OS_FAMILY" == "alpine" ]]; then
    $STD apk update
    $STD apk add --no-cache \
      gcc musl-dev linux-headers python3-dev \
      python3 py3-pip py3-virtualenv lm-sensors wireless-tools curl
  else
    $STD apt update
    $STD apt install -y \
      gcc \
      lm-sensors \
      wireless-tools \
      curl
  fi
  msg_ok "Installed dependencies"

  msg_info "Setting up Python + uv"
  setup_uv PYTHON_VERSION="3.12"
  msg_ok "Setup Python + uv"

  msg_info "Installing ${APP} (with web UI)"
  mkdir -p "$var_addon_app_dir"
  cd "$var_addon_app_dir" || exit
  $STD uv venv --clear
  source .venv/bin/activate > /dev/null 2>&1
  $STD uv pip install --upgrade pip wheel setuptools
  $STD uv pip install "glances[web]"
  deactivate
  msg_ok "Installed ${APP}"

  msg_info "Creating service"
  if [[ "$INIT_SYSTEM" == "openrc" ]]; then
    cat << EOF > "/etc/init.d/${var_addon_service}"
#!/sbin/openrc-run
command="${var_addon_app_dir}/.venv/bin/glances"
command_args="-w"
command_background="yes"
pidfile="/run/${var_addon_service}.pid"
name="${var_addon_service}"
description="Glances monitoring tool"
EOF
    chmod +x "/etc/init.d/${var_addon_service}"
    rc-update add "$var_addon_service" default
    rc-service "$var_addon_service" start
  else
    cat << EOF > "/etc/systemd/system/${var_addon_service}.service"
[Unit]
Description=Glances - An eye on your system
After=network.target

[Service]
Type=simple
ExecStart=${var_addon_app_dir}/.venv/bin/glances -w
Restart=on-failure
WorkingDirectory=${var_addon_app_dir}

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable -q --now "$var_addon_service"
  fi
  msg_ok "Created service"
}

function post_install_script() {
  echo ""
  msg_ok "${APP} installed successfully"
  echo -e "${INFO}${YW}Web UI:${CL} ${BGN}http://${LOCAL_IP}:61208${CL}"
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
}

function update_script() {
  if [[ ! -d "${var_addon_app_dir}/.venv" ]]; then
    msg_error "${APP} is not installed"
    exit 233
  fi
  msg_info "Updating ${APP}"
  cd "$var_addon_app_dir" || exit
  source .venv/bin/activate
  $STD uv pip install --upgrade "glances[web]"
  deactivate
  if [[ "$INIT_SYSTEM" == "openrc" ]]; then
    rc-service "$var_addon_service" restart
  else
    systemctl restart "$var_addon_service"
  fi
  msg_ok "Updated successfully!"
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"
  if [[ "$INIT_SYSTEM" == "openrc" ]]; then
    rc-service "$var_addon_service" stop || true
    rc-update del "$var_addon_service" || true
    rm -f "/etc/init.d/${var_addon_service}"
  else
    systemctl disable -q --now "$var_addon_service" || true
    rm -f "/etc/systemd/system/${var_addon_service}.service"
  fi
  rm -rf "$var_addon_app_dir"
  msg_ok "Removed ${APP}"
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
