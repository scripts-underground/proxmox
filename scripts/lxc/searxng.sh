#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/searxng/searxng

# shellcheck disable=SC2034
APP="SearXNG"
var_tags="${var_tags:-search}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-7}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing SearXNG dependencies"
  cat << EOF > /etc/apt/sources.list.d/backports.sources
Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie-backports
Components: main
EOF
  $STD apt update
  $STD apt install -y \
    python3-dev python3-babel python3-venv python-is-python3 \
    uwsgi uwsgi-plugin-python3 \
    git build-essential libxslt-dev zlib1g-dev libffi-dev libssl-dev valkey
  msg_ok "Installed dependencies"

  msg_info "Creating user and preparing directories"
  useradd --system --shell /bin/bash --home-dir "/usr/local/searxng" --comment 'Privacy-respecting metasearch engine' searxng || true
  mkdir -p /usr/local/searxng /etc/searxng
  chown -R searxng:searxng /usr/local/searxng /etc/searxng
  msg_ok "User and directories ready"

  msg_info "Cloning SearXNG source"
  $STD su -s /bin/bash searxng -c 'git clone https://github.com/searxng/searxng /usr/local/searxng/searxng-src'
  msg_ok "Cloned SearXNG"

  msg_info "Creating Python virtual environment"
  su -s /bin/bash searxng -c '
    python3 -m venv /usr/local/searxng/searx-pyenv &&
    . /usr/local/searxng/searx-pyenv/bin/activate &&
    pip install -U pip setuptools wheel pyyaml lxml msgspec typing_extensions &&
    pip install --use-pep517 --no-build-isolation -e /usr/local/searxng/searxng-src
  '
  msg_ok "Python environment ready"

  msg_info "Configuring SearXNG settings"
  SECRET_KEY=$(openssl rand -hex 32)
  cat << EOF > /etc/searxng/settings.yml
# SearXNG settings
use_default_settings: true
general:
  debug: false
  instance_name: "SearXNG"
  privacypolicy_url: false
  contact_url: false
server:
  bind_address: "0.0.0.0"
  port: 8888
  secret_key: "${SECRET_KEY}"
  limiter: false
  image_proxy: true
valkey:
  url: "valkey://localhost:6379/0"
ui:
  static_use_hash: true
enabled_plugins:
  - 'Hash plugin'
  - 'Self Information'
  - 'Tracker URL remover'
  - 'Ahmia blacklist'
search:
  safe_search: 2
  autocomplete: 'google'
  formats:
    - html
    - json
engines:
  - name: google
    engine: google
    shortcut: gg
    use_mobile_ui: false
  - name: duckduckgo
    engine: duckduckgo
    shortcut: ddg
    display_error_messages: true
EOF
  chown searxng:searxng /etc/searxng/settings.yml
  chmod 640 /etc/searxng/settings.yml
  msg_ok "Configured settings"

  msg_info "Set up web services"
  cat << EOF > /etc/systemd/system/searxng.service
[Unit]
Description=SearXNG service
After=network.target valkey-server.service
Wants=valkey-server.service

[Service]
Type=simple
User=searxng
Group=searxng
Environment="SEARXNG_SETTINGS_PATH=/etc/searxng/settings.yml"
ExecStart=/usr/local/searxng/searx-pyenv/bin/python -m searx.webapp
WorkingDirectory=/usr/local/searxng/searxng-src
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now searxng
  msg_ok "Created Services"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8888${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /usr/local/searxng/searxng-src ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  chown -R searxng:searxng /usr/local/searxng/searxng-src
  if su -s /bin/bash -c "git -C /usr/local/searxng/searxng-src pull" searxng | grep -q 'Already up to date'; then
    msg_ok "There is currently no update available."
    exit
  fi

  msg_info "Updating SearXNG installation"
  msg_info "Stopping Service"
  systemctl stop searxng
  msg_ok "Stopped Service"

  msg_info "Updating SearXNG"
  $STD su -s /bin/bash searxng -c '
    python3 -m venv /usr/local/searxng/searx-pyenv &&
    . /usr/local/searxng/searx-pyenv/bin/activate &&
    pip install -U pip setuptools wheel pyyaml lxml msgspec typing_extensions &&
    pip install --use-pep517 --no-build-isolation -e /usr/local/searxng/searxng-src
    '
  msg_ok "Updated SearXNG"

  msg_info "Starting Services"
  systemctl start searxng
  msg_ok "Started Services"
  msg_ok "Updated successfully!"
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
