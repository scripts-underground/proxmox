#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Marfnl (Marfnl)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/prometheus/blackbox_exporter

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Prometheus-Blackbox-Exporter"
var_tags="${var_tags:-monitoring;prometheus}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  ARCH=$(uname -m)
  [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
  fetch_and_deploy_gh_release "blackbox-exporter" "prometheus/blackbox_exporter" "prebuild" "latest" "/opt/blackbox-exporter" "blackbox_exporter-*.linux-${ARCH}.tar.gz"
  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/blackbox-exporter.service
[Unit]
Description=Blackbox Exporter Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/blackbox-exporter
ExecStart=/opt/blackbox-exporter/blackbox_exporter
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now blackbox-exporter
  msg_ok "Service Created"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:9115${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/blackbox-exporter ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "blackbox-exporter" "prometheus/blackbox_exporter"; then
    msg_info "Stopping Service"
    systemctl stop blackbox-exporter
    msg_ok "Stopped Service"

    msg_info "Creating backup"
    mv /opt/blackbox-exporter/blackbox.yml /opt
    msg_ok "Backup created"

    ARCH=$(uname -m)
    [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "blackbox-exporter" "prometheus/blackbox_exporter" "prebuild" "latest" "/opt/blackbox-exporter" "blackbox_exporter-*.linux-${ARCH}.tar.gz"

    msg_info "Restoring backup"
    cp -r /opt/blackbox.yml /opt/blackbox-exporter
    rm -f /opt/blackbox.yml
    msg_ok "Backup restored"

    msg_info "Starting Service"
    systemctl start blackbox-exporter
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
