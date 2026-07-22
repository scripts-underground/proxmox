#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/benzino77/tasmocompiler

# shellcheck disable=SC2034
APP="TasmoCompiler"
var_tags="${var_tags:-compiler}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies. Patience"
  $STD apt install -y \
    git \
    python3-venv
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" NODE_MODULE="yarn@latest" setup_nodejs

  msg_info "Setup Platformio"
  curl -fsSL -o get-platformio.py https://raw.githubusercontent.com/platformio/platformio-core-installer/master/get-platformio.py
  $STD python3 get-platformio.py
  msg_ok "Setup Platformio"

  msg_info "Setup TasmoCompiler"
  mkdir /tmp/Tasmota
  RELEASE=$(curl -fsSL https://api.github.com/repos/benzino77/tasmocompiler/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  curl_download "/tmp/v${RELEASE}.tar.gz" "https://github.com/benzino77/tasmocompiler/archive/refs/tags/v${RELEASE}.tar.gz"
  cd /tmp || exit
  tar xzf "/tmp/v${RELEASE}.tar.gz"
  mv "tasmocompiler-${RELEASE}/" /opt/tasmocompiler/
  cd /opt/tasmocompiler || exit
  $STD yarn install
  export NODE_OPTIONS=--openssl-legacy-provider
  $STD npm i
  $STD yarn build
  mkdir -p /usr/local/bin
  ln -s ~/.platformio/penv/bin/platformio /usr/local/bin/platformio
  ln -s ~/.platformio/penv/bin/pio /usr/local/bin/pio
  ln -s ~/.platformio/penv/bin/piodebuggdb /usr/local/bin/piodebuggdb
  rm -f "/tmp/v${RELEASE}.tar.gz"
  echo "${RELEASE}" > /opt/tasmocompiler_version.txt
  msg_ok "Setup TasmoCompiler"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/tasmocompiler.service
[Unit]
Description=TasmoCompiler Service
After=multi-user.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/node /opt/tasmocompiler/server/app.js

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now tasmocompiler
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/tasmocompiler ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  RELEASE=$(curl -fsSL https://api.github.com/repos/benzino77/tasmocompiler/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  if [[ ! -f /opt/tasmocompiler_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/tasmocompiler_version.txt)" ]]; then
    msg_info "Stopping Service"
    systemctl stop tasmocompiler
    msg_ok "Stopped Service"

    msg_info "Updating TasmoCompiler"
    cd /opt || exit
    rm -rf /opt/tasmocompiler
    RELEASE=$(curl -fsSL https://api.github.com/repos/benzino77/tasmocompiler/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
    curl -fsSL "https://github.com/benzino77/tasmocompiler/archive/refs/tags/v${RELEASE}.tar.gz" -o "v${RELEASE}.tar.gz"
    tar xzf "v${RELEASE}.tar.gz"
    mv "tasmocompiler-${RELEASE}/" /opt/tasmocompiler/
    cd /opt/tasmocompiler || exit
    $STD yarn install
    export NODE_OPTIONS=--openssl-legacy-provider
    $STD npm i
    $STD yarn build
    rm -f "/opt/v${RELEASE}.tar.gz"
    echo "${RELEASE}" > /opt/tasmocompiler_version.txt
    msg_ok "Updated TasmoCompiler"

    msg_info "Starting Service"
    systemctl start tasmocompiler
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
