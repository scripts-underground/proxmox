#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: BillyOutlast
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/mudler/LocalAGI

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="LocalAGI"
var_tags="${var_tags:-ai}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y build-essential
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" setup_nodejs
  setup_go

  msg_info "Installing Bun"
  export BUN_INSTALL="/root/.bun"
  curl -fsSL https://bun.sh/install | $STD bash
  ln -sf /root/.bun/bin/bun /usr/local/bin/bun
  ln -sf /root/.bun/bin/bunx /usr/local/bin/bunx
  msg_ok "Installed Bun"

  fetch_and_deploy_gh_release "localagi" "mudler/LocalAGI" "tarball" "latest" "/opt/localagi"

  msg_info "Configuring LocalAGI"
  mkdir -p /opt/localagi/pool
  cat << 'EOF' > /opt/localagi/.env
LOCALAGI_MODEL=gemma-3-4b-it-qat
LOCALAGI_MULTIMODAL_MODEL=moondream2-20250414
LOCALAGI_IMAGE_MODEL=sd-1.5-ggml
LOCALAGI_LLM_API_URL=http://127.0.0.1:11434/v1
LOCALAGI_STATE_DIR=/opt/localagi/pool
EOF
  msg_ok "Configured LocalAGI"

  msg_info "Building LocalAGI"
  cd /opt/localagi/webui/react-ui || exit
  $STD bun install
  $STD bun run build
  cd /opt/localagi || exit
  $STD go build -o /usr/local/bin/localagi
  msg_ok "Built LocalAGI"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/localagi.service
[Unit]
Description=LocalAGI
After=network.target

[Service]
User=root
Type=simple
EnvironmentFile=/opt/localagi/.env
WorkingDirectory=/opt/localagi
ExecStart=/usr/local/bin/localagi
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now localagi
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

  if [[ ! -d /opt/localagi ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "localagi" "mudler/LocalAGI"; then
    msg_info "Stopping Service"
    systemctl stop localagi
    msg_ok "Stopped Service"

    create_backup /opt/localagi/.env
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "localagi" "mudler/LocalAGI" "tarball" "latest" "/opt/localagi"
    restore_backup

    msg_info "Building LocalAGI"
    cd /opt/localagi/webui/react-ui || exit
    $STD bun install
    $STD bun run build
    cd /opt/localagi || exit
    $STD go build -o /usr/local/bin/localagi
    msg_ok "Updated LocalAGI"

    msg_info "Starting Service"
    systemctl start localagi
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
    exit
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
