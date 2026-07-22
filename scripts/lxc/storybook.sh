#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/storybookjs/storybook

# shellcheck disable=SC2034
APP="Storybook"
var_tags="${var_tags:-dev-tools;frontend;ui}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  NODE_VERSION="24" NODE_MODULE="pnpm" setup_nodejs

  msg_info "Preparing Storybook"
  mkdir -p /opt/storybook
  cd /opt/storybook || exit
  msg_ok "Important: Interactive configuration will start now."

  npx -y storybook@latest init --yes --no-dev
  PROJECT_PATH=$(find /opt/storybook -maxdepth 2 -name ".storybook" -type d 2> /dev/null | head -n1 | xargs dirname)

  if [[ -z "$PROJECT_PATH" ]]; then
    PROJECT_PATH="/opt/storybook"
  fi

  cd "$PROJECT_PATH" || exit
  echo "$PROJECT_PATH" > /opt/storybook/.projectpath

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/storybook.service
[Unit]
Description=Storybook Dev Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${PROJECT_PATH}
ExecStart=/usr/bin/npx storybook dev --host 0.0.0.0 --port 6006 --no-open
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now storybook
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:6006${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/storybook/.projectpath ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  PROJECT_PATH=$(cat /opt/storybook/.projectpath)

  if [[ ! -d "$PROJECT_PATH" ]]; then
    msg_error "Project directory not found: $PROJECT_PATH"
    exit
  fi

  msg_info "Updating Storybook"
  cd "$PROJECT_PATH" || exit
  $STD npx storybook@latest upgrade --yes
  msg_ok "Updated Storybook"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
