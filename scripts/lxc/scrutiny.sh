#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/AnalogJ/scrutiny

# shellcheck disable=SC2034
APP="Scrutiny"
var_tags="${var_tags:-monitoring;smart}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_git_repo="${var_lxc_git_repo:-AnalogJ/scrutiny}"

function install_script() {
  msg_info "Installing Scrutiny"
  local SYS_ARCH
  SYS_ARCH=$(get_system_arch)
  fetch_and_deploy_gh_release "scrutiny-web" "$var_lxc_git_repo" "binary" "latest" "/opt/scrutiny" "scrutiny-web-linux-${SYS_ARCH}"
  chmod +x "/opt/scrutiny/scrutiny-web-linux-${SYS_ARCH}"
  ln -sf "/opt/scrutiny/scrutiny-web-linux-${SYS_ARCH}" /opt/scrutiny/scrutiny-web
  fetch_and_deploy_gh_release "scrutiny-collector" "$var_lxc_git_repo" "binary" "latest" "/opt/scrutiny" "scrutiny-collector-metrics-linux-${SYS_ARCH}"
  chmod +x "/opt/scrutiny/scrutiny-collector-metrics-linux-${SYS_ARCH}"
  ln -sf "/opt/scrutiny/scrutiny-collector-metrics-linux-${SYS_ARCH}" /opt/scrutiny/scrutiny-collector
  msg_ok "Installed Scrutiny"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/scrutiny.service
[Unit]
Description=Scrutiny Web UI
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/scrutiny/scrutiny-web start --port 80
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/scrutiny-collector.service
[Unit]
Description=Scrutiny Collector
After=scrutiny.service

[Service]
Type=oneshot
User=root
ExecStart=/opt/scrutiny/scrutiny-collector run --api-endpoint http://localhost:80
EOF

  cat << EOF > /etc/systemd/system/scrutiny-collector.timer
[Unit]
Description=Scrutiny Collector Timer

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF
  systemctl enable -q --now scrutiny scrutiny-collector.timer
  msg_ok "Created Services"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  render_header
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/scrutiny ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "scrutiny-web" "$var_lxc_git_repo"; then
    msg_info "Updating ${APP}"
    systemctl stop scrutiny
    local SYS_ARCH
    SYS_ARCH=$(get_system_arch)
    fetch_and_deploy_gh_release "scrutiny-web" "$var_lxc_git_repo" "binary" "latest" "/opt/scrutiny" "scrutiny-web-linux-${SYS_ARCH}"
    chmod +x "/opt/scrutiny/scrutiny-web-linux-${SYS_ARCH}"
    ln -sf "/opt/scrutiny/scrutiny-web-linux-${SYS_ARCH}" /opt/scrutiny/scrutiny-web
    fetch_and_deploy_gh_release "scrutiny-collector" "$var_lxc_git_repo" "binary" "latest" "/opt/scrutiny" "scrutiny-collector-metrics-linux-${SYS_ARCH}"
    chmod +x "/opt/scrutiny/scrutiny-collector-metrics-linux-${SYS_ARCH}"
    ln -sf "/opt/scrutiny/scrutiny-collector-metrics-linux-${SYS_ARCH}" /opt/scrutiny/scrutiny-collector
    systemctl start scrutiny
    msg_ok "Updated successfully!"
  fi

  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
