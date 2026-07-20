#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/actions/runner

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="GitHub-Runner"
var_tags="${var_tags:-ci}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_nesting="${var_nesting:-1}"
var_keyctl="${var_keyctl:-1}"

RUNNER_ARCH=$(uname -m | sed 's/x86_64/x64/; s/aarch64/arm64/')

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    git \
    gh
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" setup_nodejs

  msg_info "Creating runner user (no sudo)"
  useradd -m -s /bin/bash runner
  msg_ok "Runner user ready"

  fetch_and_deploy_gh_release "actions-runner" "actions/runner" "prebuild" "latest" "/opt/actions-runner" "actions-runner-linux-${RUNNER_ARCH}-*.tar.gz"

  msg_info "Setting ownership for runner user"
  chown -R runner:runner /opt/actions-runner
  msg_ok "Ownership set"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/actions-runner.service
[Unit]
Description=GitHub Actions self-hosted runner
Documentation=https://docs.github.com/en/actions/hosting-your-own-runners
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=runner
WorkingDirectory=/opt/actions-runner
ExecStart=/opt/actions-runner/run.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q actions-runner
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} After first boot, run config.sh with your token and start the service.${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/actions-runner/run.sh ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  if check_for_gh_release "actions-runner" "actions/runner"; then
    msg_info "Stopping Service"
    systemctl stop actions-runner
    msg_ok "Stopped Service"

    msg_info "Backing up runner configuration"
    BACKUP_DIR="/opt/actions-runner.backup"
    mkdir -p "$BACKUP_DIR"
    for f in .runner .credentials .credentials_rsaparams .env .path; do
      [[ -f /opt/actions-runner/$f ]] && cp -a /opt/actions-runner/$f "$BACKUP_DIR/"
    done
    msg_ok "Backed up configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "actions-runner" "actions/runner" "prebuild" "latest" "/opt/actions-runner" "actions-runner-linux-${RUNNER_ARCH}-*.tar.gz"

    msg_info "Restoring runner configuration"
    for f in .runner .credentials .credentials_rsaparams .env .path; do
      [[ -f "$BACKUP_DIR/$f" ]] && cp -a "$BACKUP_DIR/$f" /opt/actions-runner/
    done
    rm -rf "$BACKUP_DIR"
    msg_ok "Restored configuration"

    msg_info "Starting Service"
    systemctl start actions-runner
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
