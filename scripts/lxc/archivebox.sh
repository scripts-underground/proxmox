#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://archivebox.io/ | Github: https://github.com/ArchiveBox/ArchiveBox

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="ArchiveBox"
var_tags="${var_tags:-archive;bookmark}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    git \
    expect \
    libssl-dev \
    libldap2-dev \
    libsasl2-dev \
    procps \
    dnsutils \
    ripgrep \
    chromium
  msg_ok "Installed Dependencies"

  msg_info "Installing Python Dependencies"
  $STD apt install -y \
    python3-ldap \
    python3-msgpack \
    python3-regex
  msg_ok "Installed Python Dependencies"

  NODE_VERSION="22" NODE_MODULE="@postlight/parser@latest,single-file-cli@latest" setup_nodejs
  PYTHON_VERSION="3.13" setup_uv

  msg_info "Installing Playwright"
  $STD uv pip install playwright --system --break-system-packages
  $STD playwright install-deps chromium
  msg_ok "Installed Playwright"

  msg_info "Installing ArchiveBox"
  mkdir -p /opt/archivebox/{data,.npm,.cache,.local}
  $STD adduser --system --shell /bin/bash --gecos 'Archive Box User' --group --disabled-password --home /home/archivebox archivebox
  chown -R archivebox:archivebox /opt/archivebox/{data,.npm,.cache,.local}
  chmod -R 755 /opt/archivebox/data
  $STD uv pip install archivebox --system --break-system-packages
  cd /opt/archivebox/data || exit
  expect << EOF
set timeout -1
log_user 0

spawn su - archivebox -c "playwright install chromium"
spawn su - archivebox -c "archivebox setup"

expect "Username"
send "\r"

expect "Email address"
send "\r"

expect "Password"
send "community-scripts.org\r"

expect "Password (again)"
send "community-scripts.org\r"

expect eof
EOF
  msg_ok "Installed ArchiveBox"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/archivebox.service
[Unit]
Description=ArchiveBox Server
After=network.target

[Service]
User=archivebox
WorkingDirectory=/opt/archivebox/data
ExecStart=/usr/local/bin/archivebox server 0.0.0.0:8000
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now archivebox
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8000/admin/login${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/archivebox ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="22" NODE_MODULE="@postlight/parser@latest,single-file-cli@latest" setup_nodejs
  PYTHON_VERSION="3.13" setup_uv

  ensure_dependencies chromium

  msg_info "Stopping Service"
  systemctl stop archivebox
  msg_ok "Stopped Service"

  msg_info "Upgrading Playwright"
  $STD uv pip install playwright --system --break-system-packages
  $STD playwright install-deps chromium
  msg_ok "Upgraded Playwright"

  msg_info "Updating ArchiveBox"
  cd /opt/archivebox/data || exit
  $STD uv pip install --system --break-system-packages --upgrade --no-reinstall archivebox
  su - archivebox -c "archivebox init"
  msg_ok "Updated ArchiveBox"

  msg_info "Starting Service"
  systemctl start archivebox
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
