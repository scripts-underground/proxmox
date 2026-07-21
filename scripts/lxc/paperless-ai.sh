#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2155,SC2046
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/clusterzx/paperless-ai

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Paperless-AI"
var_tags="${var_tags:-ai;document}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential
  msg_ok "Installed Dependencies"

  msg_info "Installing Python3"
  $STD apt install -y \
    python3-pip \
    python3-dev \
    python3-venv
  mkdir -p ~/.config/pip
  cat > ~/.config/pip/pip.conf << EOF
[global]
break-system-packages = true
EOF
  msg_ok "Installed Python3"

  NODE_VERSION="22" setup_nodejs
  fetch_and_deploy_gh_release "paperless-ai" "clusterzx/paperless-ai" "tarball"

  msg_info "Setup Paperless-AI"
  cd /opt/paperless-ai || exit
  $STD python3 -m venv /opt/paperless-ai/venv
  source /opt/paperless-ai/venv/bin/activate
  export TMPDIR=/opt/paperless-ai/tmp
  mkdir -p "$TMPDIR"
  $STD pip install --upgrade pip
  $STD pip install --no-cache-dir -r requirements.txt
  rm -rf "$TMPDIR"
  mkdir -p data/chromadb
  $STD npm ci --only=production
  mkdir -p /opt/paperless-ai/data
  cat << EOF > /opt/paperless-ai/data/.env
PAPERLESS_API_URL=
PAPERLESS_API_TOKEN=
PAPERLESS_USERNAME=
AI_PROVIDER=openai
OPENAI_API_KEY=
OPENAI_MODEL=gpt-4o-mini
OLLAMA_API_URL=
OLLAMA_MODEL=
SCAN_INTERVAL=*/10 * * * *
SYSTEM_PROMPT=""
PROCESS_PREDEFINED_DOCUMENTS=no
TAGS=
ADD_AI_PROCESSED_TAG=no
AI_PROCESSED_TAG_NAME=ki-gen
USE_PROMPT_TAGS=no
PROMPT_TAGS=
USE_EXISTING_DATA=no
API_KEY=
CUSTOM_API_KEY=
CUSTOM_BASE_URL=
CUSTOM_MODEL=
RAG_SERVICE_URL=http://localhost:8000
RAG_SERVICE_ENABLED=true
EOF
  msg_ok "Setup Paperless-AI"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/paperless-ai.service
[Unit]
Description=PaperlessAI Service
After=network.target paperless-rag.service
Requires=paperless-rag.service

[Service]
WorkingDirectory=/opt/paperless-ai
Environment="NODE_ENV=production"
EnvironmentFile=/opt/paperless-ai/data/.env
ExecStart=/usr/bin/node server.js
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/paperless-rag.service
[Unit]
Description=PaperlessAI-RAG Service
After=network.target

[Service]
WorkingDirectory=/opt/paperless-ai
EnvironmentFile=/opt/paperless-ai/data/.env
ExecStart=/opt/paperless-ai/venv/bin/python3 main.py --host 0.0.0.0 --port 8000 --initialize
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now paperless-rag
  sleep 5
  systemctl enable -q --now paperless-ai
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
  if [[ ! -d /opt/paperless-ai ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "paperless-ai" "clusterzx/paperless-ai"; then
    msg_info "Stopping Service"
    systemctl stop paperless-ai paperless-rag
    msg_ok "Stopped Service"

    msg_info "Backing up data"
    cp -r /opt/paperless-ai/data /opt/paperless-ai-data-backup
    msg_ok "Backed up data"

    fetch_and_deploy_gh_release "paperless-ai" "clusterzx/paperless-ai" "tarball"

    msg_info "Restoring data"
    cp -r /opt/paperless-ai-data-backup/* /opt/paperless-ai/data/
    rm -rf /opt/paperless-ai-data-backup
    msg_ok "Restored data"

    msg_info "Updating Paperless-AI"
    cd /opt/paperless-ai || exit
    if [[ ! -d /opt/paperless-ai/venv ]]; then
      msg_info "Recreating Python venv"
      $STD python3 -m venv /opt/paperless-ai/venv
    fi
    source /opt/paperless-ai/venv/bin/activate
    $STD pip install --upgrade pip
    $STD pip install --no-cache-dir -r requirements.txt
    mkdir -p data/chromadb
    $STD npm ci --only=production
    msg_ok "Updated Paperless-AI"

    msg_info "Starting Service"
    systemctl start paperless-rag
    sleep 3
    systemctl start paperless-ai
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
