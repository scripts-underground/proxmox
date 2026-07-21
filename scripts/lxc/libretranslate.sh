#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2155,SC2046
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/LibreTranslate/LibreTranslate

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="LibreTranslate"
var_tags="${var_tags:-arr-suite}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

function install_script() {
  setup_hwaccel

  msg_info "Installing Dependencies"
  $STD apt install -y \
    pkg-config \
    build-essential \
    g++ \
    cmake \
    libprotobuf-dev \
    protobuf-compiler \
    libsentencepiece-dev \
    libicu-dev
  msg_ok "Installed Dependencies"

  msg_info "Setup Python3"
  $STD apt install -y \
    python3-pip \
    python3-dev \
    python3-icu
  msg_ok "Setup Python3"

  PYTHON_VERSION="3.12" setup_uv
  fetch_and_deploy_gh_release "libretranslate" "LibreTranslate/LibreTranslate" "tarball"

  msg_info "Setup LibreTranslate (Patience)"
  cd /opt/libretranslate || exit
  $STD uv venv --clear .venv --python 3.12
  source .venv/bin/activate
  $STD uv pip install --upgrade pip
  $STD uv pip install "setuptools<81"
  $STD uv pip install Babel==2.12.1
  $STD .venv/bin/python scripts/compile_locales.py
  $STD uv pip install "numpy<2"
  $STD uv pip install .
  $STD uv pip install libretranslate
  $STD .venv/bin/python scripts/install_models.py

  cat << EOF > /opt/libretranslate/.env
LT_PORT=5000
EOF
  msg_ok "Installed LibreTranslate"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/libretranslate.service
[Unit]
Description=LibreTranslate
After=network.target

[Service]
User=root
Type=idle
Restart=always
Environment="PATH=/usr/local/lib/python3.11/dist-packages/libretranslate"
EnvironmentFile=/opt/libretranslate/.env
ExecStart=/opt/libretranslate/.venv/bin/python3 /opt/libretranslate/.venv/bin/libretranslate --host * --update-models
ExecReload=/bin/kill -s HUP
KillMode=mixed
TimeoutStopSec=1

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now libretranslate
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:5000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/libretranslate ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  PYTHON_VERSION="3.12" setup_uv

  if check_for_gh_release "libretranslate" "LibreTranslate/LibreTranslate"; then
    msg_info "Stopping Service"
    systemctl stop libretranslate
    msg_ok "Stopped Service"

    msg_info "Updating LibreTranslate"
    cd /opt/libretranslate || exit
    source .venv/bin/activate
    $STD uv pip install -U libretranslate
    msg_ok "Updated LibreTranslate"

    msg_info "Starting Service"
    systemctl start libretranslate
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
