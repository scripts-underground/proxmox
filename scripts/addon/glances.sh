#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster) | MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE

REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

function header_info {
  clear
  cat << "EOF"
   ________
  / ____/ /___ _____  ________  _____
 / / __/ / __ `/ __ \/ ___/ _ \/ ___/
/ /_/ / / /_/ / / / / /__/  __(__  )
\____/_/\__,_/_/ /_/\___/\___/____/

EOF
}

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Glances"
YW=$(echo "\033[33m")
GN=$(echo "\033[1;92m")
RD=$(echo "\033[01;31m")
BL=$(echo "\033[36m")
CL=$(echo "\033[m")
# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
CM="${GN}✔️${CL}"
CROSS="${RD}✖️${CL}"
INFO="${BL}ℹ️${CL}"

function msg_info() { echo -e "${INFO} ${YW}$1...${CL}"; }
function msg_ok() { echo -e "${CM} ${GN}$1${CL}"; }
function msg_error() { echo -e "${CROSS} ${RD}$1${CL}"; }

get_local_ip() {
  if command -v hostname > /dev/null 2>&1 && hostname -I 2> /dev/null; then
    hostname -I | awk '{print $1}'
  elif command -v ip > /dev/null 2>&1; then
    ip -4 addr show scope global | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1
  else
    echo "127.0.0.1"
  fi
}
IP=$(get_local_ip)

install_glances_debian() {
  msg_info "Installing dependencies"
  apt-get update > /dev/null 2>&1
  apt-get install -y gcc lm-sensors wireless-tools > /dev/null 2>&1
  msg_ok "Installed dependencies"

  msg_info "Setting up Python + uv"
  setup_uv PYTHON_VERSION="3.12"
  msg_ok "Setup Python + uv"

  msg_info "Installing $APP (with web UI)"
  cd /opt || exit
  mkdir -p glances
  cd glances || exit
  uv venv
  source .venv/bin/activate > /dev/null 2>&1
  uv pip install --upgrade pip wheel setuptools > /dev/null 2>&1
  uv pip install "glances[web]" > /dev/null 2>&1
  deactivate
  msg_ok "Installed $APP"

  msg_info "Creating systemd service"
  cat << EOF > /etc/systemd/system/glances.service
[Unit]
Description=Glances - An eye on your system
After=network.target

[Service]
Type=simple
ExecStart=/opt/glances/.venv/bin/glances -w
Restart=on-failure
WorkingDirectory=/opt/glances

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now glances
  msg_ok "Created systemd service"
}

update_glances_debian() {
  if [[ ! -d /opt/glances/.venv ]]; then
    msg_error "$APP is not installed"
    exit 1
  fi
  msg_info "Updating $APP"
  cd /opt/glances || exit
  source .venv/bin/activate
  uv pip install --upgrade "glances[web]" > /dev/null 2>&1
  deactivate
  systemctl restart glances
  msg_ok "Updated $APP"
}

uninstall_glances_debian() {
  msg_info "Uninstalling $APP"
  systemctl disable -q --now glances || true
  rm -f /etc/systemd/system/glances.service
  rm -rf /opt/glances
  msg_ok "Removed $APP"
}

install_glances_alpine() {
  msg_info "Installing dependencies"
  apk update > /dev/null 2>&1
  $STD apk add --no-cache \
    gcc musl-dev linux-headers python3-dev \
    python3 py3-pip py3-virtualenv lm-sensors wireless-tools > /dev/null 2>&1
  msg_ok "Installed dependencies"

  msg_info "Setting up Python + uv"
  setup_uv PYTHON_VERSION="3.12"
  msg_ok "Setup Python + uv"

  msg_info "Installing $APP (with web UI)"
  cd /opt || exit
  mkdir -p glances
  cd glances || exit
  uv venv
  source .venv/bin/activate
  uv pip install --upgrade pip wheel setuptools > /dev/null 2>&1
  uv pip install "glances[web]" > /dev/null 2>&1
  deactivate
  msg_ok "Installed $APP"

  msg_info "Creating OpenRC service"
  cat << 'ALPEOF' > /etc/init.d/glances
#!/sbin/openrc-run
command="/opt/glances/.venv/bin/glances"
command_args="-w"
command_background="yes"
pidfile="/run/glances.pid"
name="glances"
description="Glances monitoring tool"
ALPEOF
  chmod +x /etc/init.d/glances
  rc-update add glances default
  rc-service glances start
  msg_ok "Created OpenRC service"
}

update_glances_alpine() {
  if [[ ! -d /opt/glances/.venv ]]; then
    msg_error "$APP is not installed"
    exit 1
  fi
  msg_info "Updating $APP"
  cd /opt/glances || exit
  source .venv/bin/activate
  uv pip install --upgrade "glances[web]" > /dev/null 2>&1
  deactivate
  rc-service glances restart
  msg_ok "Updated $APP"
}

uninstall_glances_alpine() {
  msg_info "Uninstalling $APP"
  rc-service glances stop || true
  rc-update del glances || true
  rm -f /etc/init.d/glances
  rm -rf /opt/glances
  msg_ok "Removed $APP"
}

function install_script() {
  if grep -qi "alpine" /etc/os-release; then
    install_glances_alpine
  else
    install_glances_debian
  fi
}

function update_script() {
  if grep -qi "alpine" /etc/os-release; then
    update_glances_alpine
  else
    update_glances_debian
  fi
}

function uninstall_script() {
  if grep -qi "alpine" /etc/os-release; then
    uninstall_glances_alpine
  else
    uninstall_glances_debian
  fi
}

function post_install_script() {
  echo -e "\n$APP is now running at: http://$IP:61208\n"
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon")
