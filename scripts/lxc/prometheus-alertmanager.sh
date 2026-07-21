#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Andy Grunwald (andygrunwald)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://prometheus.io/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Prometheus-Alertmanager"
var_tags="${var_tags:-monitoring;alerting}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  ARCH=$(uname -m)
  [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"

  fetch_and_deploy_gh_release "alertmanager" "prometheus/alertmanager" "prebuild" "latest" "/usr/local/bin/" "alertmanager*linux-${ARCH}.tar.gz"

  msg_info "Configuring Prometheus Alertmanager"
  mkdir -p /etc/alertmanager /var/lib/alertmanager
  mv /usr/local/bin/alertmanager.yml /etc/alertmanager/alertmanager.yml
  msg_ok "Configured Prometheus Alertmanager"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/prometheus-alertmanager.service
[Unit]
Description=Prometheus Alertmanager
Wants=network-online.target
After=network-online.target

[Service]
User=root
Restart=always
Type=simple
ExecStart=/usr/local/bin/alertmanager \
    --config.file=/etc/alertmanager/alertmanager.yml \
    --storage.path=/var/lib/alertmanager/ \
    --web.listen-address=0.0.0.0:9093
ExecReload=/bin/kill -HUP \$MAINPID

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now prometheus-alertmanager
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9093${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/prometheus-alertmanager.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "alertmanager" "prometheus/alertmanager"; then
    msg_info "Stopping Service"
    systemctl stop prometheus-alertmanager
    msg_ok "Stopped Service"

    ARCH=$(uname -m)
    [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
    fetch_and_deploy_gh_release "alertmanager" "prometheus/alertmanager" "prebuild" "latest" "/usr/local/bin/" "alertmanager*linux-${ARCH}.tar.gz"

    msg_info "Starting Service"
    systemctl start prometheus-alertmanager
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
