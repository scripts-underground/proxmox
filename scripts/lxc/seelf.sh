#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/YuukanOO/seelf

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="seelf"
var_tags="${var_tags:-server;docker}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    make \
    gcc
  msg_ok "Installed Dependencies"

  setup_go
  NODE_VERSION="22" setup_nodejs
  fetch_and_deploy_gh_release "seelf" "YuukanOO/seelf" "tarball"

  msg_info "Setting up seelf. Patience"
  cd /opt/seelf || exit
  $STD make build
  PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  mkdir -p /opt/seelf/data
  {
    echo "ADMIN_EMAIL=admin@example.com"
    echo "ADMIN_PASSWORD=$PASS"
  } | tee .env ~/seelf.creds > /dev/null
  SEELF_ADMIN_EMAIL=admin@example.com SEELF_ADMIN_PASSWORD=$PASS ./seelf serve &> /dev/null &
  sleep 5
  kill $! 2> /dev/null || true
  msg_ok "Done setting up seelf"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/seelf.service
[Unit]
Description=seelf Service
After=network.target

[Service]
Type=simple
User=root
Group=root
EnvironmentFile=/opt/seelf/.env
Environment=DATA_PATH=/opt/seelf/data
WorkingDirectory=/opt/seelf
ExecStart=/opt/seelf/./seelf -c data/conf.yml serve
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now seelf
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/seelf ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "seelf" "YuukanOO/seelf"; then
    msg_info "Stopping Service"
    systemctl stop seelf
    msg_ok "Stopped Service"

    msg_info "Updating seelf"
    cd /opt/seelf || exit
    $STD make build
    msg_ok "Updated seelf"

    msg_info "Starting Service"
    systemctl start seelf
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
