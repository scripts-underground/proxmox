#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Andy Grunwald (andygrunwald)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/prometheus-pve/prometheus-pve-exporter

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Prometheus-PVE-Exporter"
var_tags="${var_tags:-monitoring}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  PYTHON_VERSION="3.12" setup_uv

  msg_info "Installing Prometheus Proxmox VE Exporter"
  mkdir -p /opt/prometheus-pve-exporter
  cd /opt/prometheus-pve-exporter || exit

  $STD uv venv --clear /opt/prometheus-pve-exporter/.venv
  $STD /opt/prometheus-pve-exporter/.venv/bin/python -m ensurepip --upgrade
  $STD /opt/prometheus-pve-exporter/.venv/bin/python -m pip install --upgrade pip
  $STD /opt/prometheus-pve-exporter/.venv/bin/python -m pip install prometheus-pve-exporter
  cat << EOF > /opt/prometheus-pve-exporter/pve.yml
default:
    user: prometheus@pve
    password: sEcr3T!
    verify_ssl: false
EOF
  msg_ok "Installed Prometheus Proxmox VE Exporter"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/prometheus-pve-exporter.service
[Unit]
Description=Prometheus Proxmox VE Exporter
Documentation=https://github.com/znerol/prometheus-pve-exporter
After=syslog.target network.target

[Service]
User=root
Restart=always
Type=simple
ExecStart=/opt/prometheus-pve-exporter/.venv/bin/pve_exporter \\
    --config.file=/opt/prometheus-pve-exporter/pve.yml \\
    --web.listen-address=0.0.0.0:9221
ExecReload=/bin/kill -HUP \$MAINPID

[Install]
WantedBy=multi-user.target
EOF

  systemctl enable -q --now prometheus-pve-exporter
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:9221${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/prometheus-pve-exporter.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop prometheus-pve-exporter
  msg_ok "Stopped Service"

  export PVE_VENV_PATH="/opt/prometheus-pve-exporter/.venv"
  export PVE_EXPORTER_BIN="${PVE_VENV_PATH}/bin/pve_exporter"

  if [[ ! -d "$PVE_VENV_PATH" || ! -x "$PVE_EXPORTER_BIN" ]]; then
    PYTHON_VERSION="3.12" setup_uv
    msg_info "Migrating to uv/venv"
    rm -rf "$PVE_VENV_PATH"
    mkdir -p /opt/prometheus-pve-exporter
    cd /opt/prometheus-pve-exporter || exit
    $STD uv venv --clear "$PVE_VENV_PATH"
    $STD "$PVE_VENV_PATH/bin/python" -m ensurepip --upgrade
    $STD "$PVE_VENV_PATH/bin/python" -m pip install --upgrade pip
    $STD "$PVE_VENV_PATH/bin/python" -m pip install prometheus-pve-exporter
    msg_ok "Migrated to uv/venv"
  else
    msg_info "Updating Prometheus Proxmox VE Exporter"
    PYTHON_VERSION="3.12" setup_uv
    $STD "$PVE_VENV_PATH/bin/python" -m pip install --upgrade prometheus-pve-exporter
    msg_ok "Updated Prometheus Proxmox VE Exporter"
  fi
  local service_file="/etc/systemd/system/prometheus-pve-exporter.service"
  if ! grep -q "${PVE_VENV_PATH}/bin/pve_exporter" "$service_file"; then
    msg_info "Updating systemd service"
    cat << EOF > "$service_file"
[Unit]
Description=Prometheus Proxmox VE Exporter
Documentation=https://github.com/znerol/prometheus-pve-exporter
After=syslog.target network.target

[Service]
User=root
Restart=always
Type=simple
ExecStart=${PVE_VENV_PATH}/bin/pve_exporter \\
    --config.file=/opt/prometheus-pve-exporter/pve.yml \\
    --web.listen-address=0.0.0.0:9221
ExecReload=/bin/kill -HUP \$MAINPID

[Install]
WantedBy=multi-user.target
EOF
    $STD systemctl daemon-reload
    msg_ok "Updated systemd service"
  fi

  msg_info "Starting Service"
  systemctl start prometheus-pve-exporter
  msg_ok "Started Service"

  msg_ok "Updated successfully!"
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
