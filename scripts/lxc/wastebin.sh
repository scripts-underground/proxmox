#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2155,SC2046
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/matze/wastebin

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Wastebin"
var_tags="${var_tags:-file;code}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing dependencies"
  $STD apt install -y zstd
  msg_ok "Installed dependencies"

  msg_info "Installing Wastebin"
  temp_file=$(mktemp)
  RELEASE=$(curl -fsSL https://api.github.com/repos/matze/wastebin/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
  curl -fsSL "https://github.com/matze/wastebin/releases/download/${RELEASE}/wastebin_${RELEASE}_$(uname -m)-unknown-linux-musl.tar.zst" -o "$temp_file"
  tar -xf "$temp_file"
  mkdir -p /opt/wastebin
  mv wastebin* /opt/wastebin/
  chmod +x /opt/wastebin/wastebin
  chmod +x /opt/wastebin/wastebin-ctl

  mkdir -p /opt/wastebin-data
  cat << EOF > /opt/wastebin-data/.env
WASTEBIN_DATABASE_PATH=/opt/wastebin-data/wastebin.db
WASTEBIN_CACHE_SIZE=1024
WASTEBIN_HTTP_TIMEOUT=30
WASTEBIN_SIGNING_KEY=$(openssl rand -hex 32)
WASTEBIN_PASTE_EXPIRATIONS=0,600,3600=d,86400,604800,2419200,29030400
EOF
  rm -f "$temp_file"
  echo "${RELEASE}" > "/opt/${APP}_version.txt"

  msg_ok "Installed Wastebin"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/wastebin.service
[Unit]
Description=Start Wastebin Service
After=network.target

[Service]
WorkingDirectory=/opt/wastebin
ExecStart=/opt/wastebin/wastebin
EnvironmentFile=/opt/wastebin-data/.env

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now wastebin
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8088${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/wastebin ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  ensure_dependencies zstd
  RELEASE=$(curl -fsSL https://api.github.com/repos/matze/wastebin/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
  # Dirty-Fix 03/2025 for missing APP_version.txt on old installations, set to pre-latest release
  msg_info "Running Migration"
  if [[ ! -f /opt/${APP}_version.txt ]]; then
    echo "2.7.1" > /opt/${APP}_version.txt
    mkdir -p /opt/wastebin-data
    cat << EOF > /opt/wastebin-data/.env
WASTEBIN_DATABASE_PATH=/opt/wastebin-data/wastebin.db
WASTEBIN_CACHE_SIZE=1024
WASTEBIN_HTTP_TIMEOUT=30
WASTEBIN_SIGNING_KEY=$(openssl rand -hex 32)
WASTEBIN_PASTE_EXPIRATIONS=0,600,3600=d,86400,604800,2419200,29030400
EOF
    systemctl stop wastebin
    cat << EOF > /etc/systemd/system/wastebin.service
[Unit]
Description=Wastebin Service
After=network.target

[Service]
WorkingDirectory=/opt/wastebin
ExecStart=/opt/wastebin/wastebin
EnvironmentFile=/opt/wastebin-data/.env

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
  fi
  msg_ok "Migration Done"
  if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
    msg_info "Stopping Wastebin"
    systemctl stop wastebin
    msg_ok "Wastebin Stopped"

    msg_info "Updating Wastebin"
    temp_file=$(mktemp)
    curl -fsSL "https://github.com/matze/wastebin/releases/download/${RELEASE}/wastebin_${RELEASE}_$(uname -m)-unknown-linux-musl.tar.zst" -o "$temp_file"
    tar -xf "$temp_file"
    cp -f wastebin* /opt/wastebin/
    chmod +x /opt/wastebin/wastebin
    chmod +x /opt/wastebin/wastebin-ctl
    rm -f "$temp_file"
    echo "${RELEASE}" > /opt/${APP}_version.txt
    msg_ok "Updated Wastebin"

    msg_info "Starting Wastebin"
    systemctl start wastebin
    msg_ok "Started Wastebin"
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
