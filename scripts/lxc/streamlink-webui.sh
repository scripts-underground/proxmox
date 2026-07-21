#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/CrazyWolf13/streamlink-webui

# shellcheck disable=SC2034
APP="streamlink-webui"
var_tags="${var_tags:-download;streaming}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  NODE_VERSION="22" NODE_MODULE="npm@latest,yarn@latest" setup_nodejs
  setup_uv
  fetch_and_deploy_gh_release "streamlink-webui" "CrazyWolf13/streamlink-webui" "tarball"

  msg_info "Setup streamlink-webui"
  mkdir -p "/opt/streamlink-webui-download"
  $STD uv venv --clear /opt/streamlink-webui/backend/src/.venv
  source /opt/streamlink-webui/backend/src/.venv/bin/activate
  $STD uv pip install -r /opt/streamlink-webui/backend/src/requirements.txt --python=/opt/streamlink-webui/backend/src/.venv
  cd /opt/streamlink-webui/frontend/src || exit
  $STD yarn install
  $STD yarn build
  chmod +x /opt/streamlink-webui/start.sh
  msg_ok "Setup streamlink-webui"

  msg_info "Creating Service"
  cat << 'EOF' > /opt/streamlink-webui.env
CLIENT_ID='your_client_id'
CLIENT_SECRET='your_client_secret'
DOWNLOAD_PATH='/opt/streamlink-webui-download'
# BASE_URL='https://sub.domain.com' \
# REVERSE_PROXY=True \
EOF

  cat << EOF > /etc/systemd/system/streamlink-webui.service
[Unit]
Description=streamlink-webui Service
After=network.target

[Service]
EnvironmentFile=/opt/streamlink-webui.env
WorkingDirectory=/opt/streamlink-webui/backend/src
ExecStart=/bin/bash -c 'source /opt/streamlink-webui/backend/src/.venv/bin/activate && exec /opt/streamlink-webui/start.sh'
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now streamlink-webui
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/streamlink-webui ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "streamlink-webui" "CrazyWolf13/streamlink-webui"; then
    msg_info "Stopping Service"
    systemctl stop streamlink-webui
    msg_ok "Stopped Service"

    NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs
    setup_uv
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "streamlink-webui" "CrazyWolf13/streamlink-webui" "tarball"

    msg_info "Updating streamlink-webui"
    $STD uv venv --clear /opt/streamlink-webui/backend/src/.venv
    source /opt/streamlink-webui/backend/src/.venv/bin/activate
    $STD uv pip install -r /opt/streamlink-webui/backend/src/requirements.txt --python=/opt/streamlink-webui/backend/src/.venv
    cd /opt/streamlink-webui/frontend/src || exit
    $STD yarn install
    $STD yarn build
    chmod +x /opt/streamlink-webui/start.sh
    msg_ok "Updated streamlink-webui"

    msg_info "Starting Service"
    systemctl start streamlink-webui
    msg_ok "Started Service"
    msg_ok "Updated Successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
