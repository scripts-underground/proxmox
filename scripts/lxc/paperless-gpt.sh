#!/usr/bin/env bash
# shellcheck disable=SC2034
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/icereed/paperless-gpt

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Paperless-GPT"
var_tags="${var_tags:-os}"
var_cpu="${var_cpu:-3}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-7}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    gcc \
    musl-dev \
    mupdf \
    libc6-dev \
    musl-tools
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" setup_nodejs
  setup_go
  fetch_and_deploy_gh_release "paperless-gpt" "icereed/paperless-gpt" "tarball"

  msg_info "Setup Paperless-GPT"
  cd /opt/paperless-gpt/web-app || exit
  $STD npm install
  $STD npm run build
  cd /opt/paperless-gpt || exit
  go mod download
  export CC=musl-gcc
  CGO_ENABLED=1 go build -tags musl -o /dev/null github.com/mattn/go-sqlite3
  CGO_ENABLED=1 go build -tags musl -o paperless-gpt .
  msg_ok "Setup Paperless-GPT"

  mkdir -p /opt/paperless-gpt-data

  msg_info "Setup Environment"
  PAPERLESS_BASE_URL="http://your_paperless_ngx_url"
  PAPERLESS_API_TOKEN="your_paperless_api_token"
  cat << EOF > /opt/paperless-gpt-data/.env
PAPERLESS_BASE_URL=$PAPERLESS_BASE_URL
PAPERLESS_API_TOKEN=$PAPERLESS_API_TOKEN

LLM_PROVIDER=openai
LLM_MODEL=gpt-4o
OPENAI_API_KEY=your_openai_api_key

#VISION_LLM_PROVIDER=ollama
#VISION_LLM_MODEL=minicpm-v

LLM_LANGUAGE=English
LOG_LEVEL=info

LISTEN_INTERFACE=:8080

AUTO_TAG=paperless-gpt-auto
MANUAL_TAG=paperless-gpt
AUTO_OCR_TAG=paperless-gpt-ocr-auto

OCR_LIMIT_PAGES=5
EOF
  msg_ok "Setup Environment"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/paperless-gpt.service
[Unit]
Description=Paperless-GPT
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/paperless-gpt
ExecStart=/opt/paperless-gpt/paperless-gpt
Restart=always
User=root
EnvironmentFile=/opt/paperless-gpt-data/.env
StandardOutput=append:/var/log/paperless-gpt.log
StandardError=append:/var/log/paperless-gpt.log

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now paperless-gpt
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
  echo -e "\n${INFO}${YW}Configure your Paperless-NGX connection in /opt/paperless-gpt-data/.env${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/paperless-gpt ]]; then
    msg_error "No Paperless-GPT installation found!"
    exit
  fi

  if check_for_gh_release "paperless-gpt" "icereed/paperless-gpt"; then
    msg_info "Stopping Service"
    systemctl stop paperless-gpt
    msg_ok "Service Stopped"

    if should_update_tool "node" "24"; then
      NODE_VERSION="24" setup_nodejs
    fi

    fetch_and_deploy_gh_release "paperless-gpt" "icereed/paperless-gpt" "tarball"

    msg_info "Updating Paperless-GPT"
    cd /opt/paperless-gpt/web-app || exit
    $STD npm install
    $STD npm run build
    cd /opt/paperless-gpt || exit
    go mod download
    export CC=musl-gcc
    CGO_ENABLED=1 go build -tags musl -o /dev/null github.com/mattn/go-sqlite3
    CGO_ENABLED=1 go build -tags musl -o paperless-gpt .
    msg_ok "Updated Paperless-GPT"

    msg_info "Starting Service"
    systemctl start paperless-gpt
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
