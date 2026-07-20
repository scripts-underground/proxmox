#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck | Co-Author: havardthom | Co-Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://openwebui.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Open WebUI"
var_tags="${var_tags:-ai;interface}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-50}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    ffmpeg \
    zstd \
    build-essential \
    libmariadb-dev
  msg_ok "Installed Dependencies"

  setup_hwaccel

  PYTHON_VERSION="3.12" setup_uv

  msg_info "Installing Open WebUI"
  $STD uv tool install --python 3.12 --constraint <(echo "numba>=0.60") open-webui[all]
  msg_ok "Installed Open WebUI"

  read -r -p "${TAB3}Would you like to add Ollama? <y/N> " prompt
  if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
    if [[ "$(dpkg --print-architecture)" == "amd64" ]]; then
      msg_info "Setting up Intel\u00ae Repositories"
      mkdir -p /usr/share/keyrings
      curl -fsSL https://repositories.intel.com/gpu/intel-graphics.key | gpg --dearmor -o /usr/share/keyrings/intel-graphics.gpg 2> /dev/null || true
      cat << EOF > /etc/apt/sources.list.d/intel-gpu.sources
Types: deb
URIs: https://repositories.intel.com/gpu/ubuntu
Suites: jammy
Components: client
Architectures: amd64 i386
Signed-By: /usr/share/keyrings/intel-graphics.gpg
EOF
      curl -fsSL https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB | gpg --dearmor -o /usr/share/keyrings/oneapi-archive-keyring.gpg 2> /dev/null || true
      cat << EOF > /etc/apt/sources.list.d/oneAPI.sources
Types: deb
URIs: https://apt.repos.intel.com/oneapi
Suites: all
Components: main
Signed-By: /usr/share/keyrings/oneapi-archive-keyring.gpg
EOF
      $STD apt update
      msg_ok "Set up Intel\u00ae Repositories"

      msg_info "Installing Intel\u00ae Level Zero"
      if is_debian && [[ "$(get_os_version_major)" -ge 13 ]]; then
        $STD apt -y install libze1 libze-dev intel-level-zero-gpu 2> /dev/null || {
          msg_warn "Failed to install some Level Zero packages, continuing anyway"
        }
      else
        $STD apt -y install intel-level-zero-gpu level-zero level-zero-dev 2> /dev/null || {
          msg_warn "Failed to install Intel Level Zero packages, continuing anyway"
        }
      fi
      msg_ok "Installed Intel\u00ae Level Zero"

      msg_info "Installing Intel\u00ae oneAPI Base Toolkit (Patience)"
      $STD apt install -y --no-install-recommends intel-basekit-2024.1 2> /dev/null || true
      msg_ok "Installed Intel\u00ae oneAPI Base Toolkit"
    fi

    msg_info "Installing Ollama"
    if ! fetch_and_deploy_gh_release "ollama-com" "ollama/ollama" "prebuild" "latest" "/usr/lib/ollama" "ollama-linux-$(dpkg --print-architecture).tar.zst"; then
      msg_error "Failed to download or deploy Ollama \u2013 check network connectivity and GitHub API availability"
    else
      ln -sf /usr/lib/ollama/bin/ollama /usr/bin/ollama
      cat << EOF > /etc/systemd/system/ollama.service
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
Type=exec
ExecStart=/usr/bin/ollama serve
Environment=HOME=$HOME
Environment=OLLAMA_HOST=0.0.0.0
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
      systemctl enable -q --now ollama
      echo "ENABLE_OLLAMA_API=true" > /root/.env
      msg_ok "Installed Ollama"
    fi
  fi

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/open-webui.service
[Unit]
Description=Open WebUI Service
After=network.target

[Service]
Type=simple
EnvironmentFile=-/root/.env
Environment=DATA_DIR=/root/.open-webui
ExecStart=/root/.local/bin/open-webui serve
WorkingDirectory=/root
Restart=on-failure
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now open-webui
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  ensure_dependencies zstd build-essential libmariadb-dev
  [[ -f /root/.ollama ]] && rm -f /root/.ollama

  if [[ -d /opt/open-webui ]]; then
    msg_warn "Legacy installation detected \u2014 migrating to uv based install..."
    msg_info "Stopping Service"
    systemctl stop open-webui
    msg_ok "Stopped Service"

    msg_info "Creating Backup"
    mkdir -p /opt/open-webui-backup
    cp -a /opt/open-webui/backend/data /opt/open-webui-backup/data || true
    cp -a /opt/open-webui/.env /opt/open-webui-backup/.env || true
    msg_ok "Created Backup"

    msg_info "Removing legacy installation"
    rm -rf /opt/open-webui
    rm -rf /root/.open-webui || true
    msg_ok "Removed legacy installation"

    msg_info "Installing uv-based Open-WebUI"
    PYTHON_VERSION="3.12" setup_uv
    $STD uv tool install --python 3.12 --constraint <(echo "numba>=0.60") open-webui[all]
    msg_ok "Installed uv-based Open-WebUI"

    msg_info "Restoring data"
    mkdir -p /root/.open-webui
    cp -a /opt/open-webui-backup/data/* /root/.open-webui/ || true
    cp -a /opt/open-webui-backup/.env /root/.env || true
    rm -rf /opt/open-webui-backup || true
    msg_ok "Restored data"

    msg_info "Recreating Service"
    cat << EOF > /etc/systemd/system/open-webui.service
[Unit]
Description=Open WebUI Service
After=network.target

[Service]
Type=simple
Environment=DATA_DIR=/root/.open-webui
EnvironmentFile=-/root/.env
ExecStart=/root/.local/bin/open-webui serve
WorkingDirectory=/root
Restart=on-failure
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

    $STD systemctl daemon-reload
    systemctl enable -q --now open-webui
    msg_ok "Recreated Service"

    msg_ok "Migration completed"
    exit 0
  fi

  if [[ ! -d /root/.open-webui ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if [ -x "/usr/bin/ollama" ]; then
    msg_info "Checking for Ollama Update"
    if check_for_gh_release "ollama-com" "ollama/ollama"; then
      msg_info "Stopping Ollama Service"
      systemctl stop ollama
      msg_ok "Stopped Service"

      rm -rf /usr/lib/ollama /usr/bin/ollama
      if ! fetch_and_deploy_gh_release "ollama-com" "ollama/ollama" "prebuild" "latest" "/usr/lib/ollama" "ollama-linux-$(dpkg --print-architecture).tar.zst"; then
        msg_error "Ollama download or deployment failed \u2013 check network connectivity and GitHub API availability"
      else
        ln -sf /usr/lib/ollama/bin/ollama /usr/bin/ollama
        msg_ok "Updated Ollama to ${CHECK_UPDATE_RELEASE}"
      fi

      msg_info "Starting Ollama Service"
      systemctl start ollama
      msg_ok "Started Service"
    fi
  fi

  msg_info "Updating Open WebUI via uv"
  PYTHON_VERSION="3.12" setup_uv
  $STD uv tool install --force --python 3.12 --constraint <(echo "numba>=0.60") open-webui[all]
  systemctl restart open-webui
  msg_ok "Updated Open WebUI"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
