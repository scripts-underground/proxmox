#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/open-webui/open-webui

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Open WebUI"
var_tags="${var_tags:-ai;llm}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_git_repo="${var_lxc_git_repo:-open-webui/open-webui}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git curl
  msg_ok "Installed Dependencies"

  PYTHON_VERSION="3.13" setup_uv

  msg_info "Installing Open WebUI"
  $STD uv pip install --system open-webui
  msg_ok "Installed Open WebUI"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/openwebui.service
[Unit]
Description=Open WebUI
After=network.target

[Service]
Type=simple
User=root
Environment=HOME=/root
ExecStart=/usr/local/bin/open-webui serve --port 80
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now openwebui
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
  echo -e "${INFO}${YW}After first login, connect a model provider (Ollama, OpenAI-compatible API) in the admin settings.${CL}"
}

function update_script() {
  render_header
  check_container_storage
  check_container_resources

  if [[ ! -f /usr/local/bin/open-webui ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  PYTHON_VERSION="3.13" setup_uv
  msg_info "Updating ${APP}"
  systemctl stop openwebui
  $STD uv pip install --system --upgrade open-webui
  systemctl start openwebui
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc") --script-id "openwebui" -- "$@"
