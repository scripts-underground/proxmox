#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://fumadocs.vercel.app/

# shellcheck disable=SC2034
APP="Fumadocs"
var_tags="${var_tags:-documentation}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  $STD apt install -y ca-certificates git
  NODE_VERSION="24" NODE_MODULE="pnpm@latest" setup_nodejs

  read -r -p "${TAB3}Enter project name for Fumadocs (default: fumadocs): " PROJECT_NAME
  PROJECT_NAME=${PROJECT_NAME:-fumadocs}

  msg_info "Setting up Fumadocs"
  mkdir -p /opt/fumadocs
  cd /opt/fumadocs || exit
  $STD pnpm create fumadocs-app "$PROJECT_NAME"

  echo "$PROJECT_NAME" > /opt/fumadocs/.projectname
  msg_ok "Set up Fumadocs"

  msg_info "Creating Service"
  cat << EOF > "/etc/systemd/system/fumadocs_${PROJECT_NAME}.service"
[Unit]
Description=Fumadocs ${PROJECT_NAME} Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/fumadocs/${PROJECT_NAME}
ExecStart=/usr/bin/pnpm run dev
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now "fumadocs_${PROJECT_NAME}"
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/fumadocs ]]; then
    msg_error "No installation found in /opt/fumadocs!"
    exit
  fi

  if [[ ! -f /opt/fumadocs/.projectname ]]; then
    msg_error "Project name file not found: /opt/fumadocs/.projectname!"
    exit
  fi

  NODE_VERSION="24" NODE_MODULE="pnpm@latest" setup_nodejs
  PROJECT_NAME=$(< /opt/fumadocs/.projectname)
  PROJECT_DIR="/opt/fumadocs/${PROJECT_NAME}"
  SERVICE_NAME="fumadocs_${PROJECT_NAME}.service"

  if [[ ! -d "$PROJECT_DIR" ]]; then
    msg_error "Project directory does not exist: $PROJECT_DIR"
    exit
  fi
  ensure_dependencies git

  msg_info "Stopping service $SERVICE_NAME"
  systemctl stop "$SERVICE_NAME"
  msg_ok "Stopped service $SERVICE_NAME"

  msg_info "Updating dependencies using pnpm"
  cd "$PROJECT_DIR" || exit
  $STD pnpm up --latest
  $STD pnpm build
  msg_ok "Updated dependencies using pnpm"

  msg_info "Starting service $SERVICE_NAME"
  systemctl start "$SERVICE_NAME"
  msg_ok "Started service $SERVICE_NAME"
  msg_ok "Updated successfully!"
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
