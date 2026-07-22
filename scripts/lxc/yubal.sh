#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Crazywolf13
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/guillevc/yubal

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Yubal"
var_tags="${var_tags:-music;media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-15}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    libssl-dev \
    libffi-dev \
    python3-dev \
    ffmpeg \
    git
  msg_ok "Installed Dependencies"

  msg_info "Installing Bun"
  export BUN_INSTALL=/opt/bun
  curl -fsSL https://bun.sh/install | $STD bash
  ln -sf /opt/bun/bin/bun /usr/local/bin/bun
  ln -sf /opt/bun/bin/bunx /usr/local/bin/bunx
  msg_ok "Installed Bun"

  UV_VERSION="0.7.19" PYTHON_VERSION="3.12" setup_uv

  msg_info "Installing Deno"
  $STD sh -c "curl -fsSL https://deno.land/install.sh | DENO_INSTALL=/usr/local sh -s -- -y"
  msg_ok "Installed Deno"

  msg_info "Creating directories"
  mkdir -p /opt/yubal \
    /opt/yubal_data \
    /opt/yubal_config
  msg_ok "Created directories"

  fetch_and_deploy_gh_release "yubal" "guillevc/yubal" "tarball" "latest" "/opt/yubal"

  msg_info "Building Frontend"
  cd /opt/yubal/web || exit
  $STD bun install --frozen-lockfile
  VERSION=$(get_latest_github_release "guillevc/yubal")
  VITE_VERSION=$VERSION VITE_COMMIT_SHA=$VERSION VITE_IS_RELEASE=true $STD bun run build
  msg_ok "Built Frontend"

  msg_info "Installing Python Dependencies"
  cd /opt/yubal || exit
  export UV_CONCURRENT_DOWNLOADS=1
  $STD uv sync --package yubal-api --no-dev --frozen
  msg_ok "Installed Python Dependencies"

  msg_info "Creating Service"
  cat << EOF > /opt/yubal.env
YUBAL_HOST=0.0.0.0
YUBAL_PORT=8000
YUBAL_DATA=/opt/yubal_data
YUBAL_CONFIG=/opt/yubal_config
YUBAL_ROOT=/opt/yubal
PYTHONUNBUFFERED=1
EOF
  cat << EOF > /etc/systemd/system/yubal.service
[Unit]
Description=Yubal
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/yubal
EnvironmentFile=/opt/yubal.env
Environment="PATH=/opt/yubal/.venv/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=/opt/yubal/.venv/bin/python -m yubal_api
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now yubal
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/yubal ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  ensure_dependencies git

  if check_for_gh_release "yubal" "guillevc/yubal"; then
    msg_info "Stopping Services"
    systemctl stop yubal
    msg_ok "Stopped Services"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "yubal" "guillevc/yubal" "tarball" "latest" "/opt/yubal"

    msg_info "Building Frontend"
    cd /opt/yubal/web || exit
    $STD bun install --frozen-lockfile
    VERSION=$(get_latest_github_release "guillevc/yubal")
    VITE_VERSION=$VERSION VITE_COMMIT_SHA=$VERSION VITE_IS_RELEASE=true $STD bun run build
    msg_ok "Built Frontend"

    msg_info "Installing Python Dependencies"
    cd /opt/yubal || exit
    $STD uv sync --package yubal-api --no-dev --frozen
    msg_ok "Installed Python Dependencies"

    msg_info "Starting Services"
    systemctl start yubal
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
