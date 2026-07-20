#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Dave-code-creater (Tan Dat, Ta)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://jupyter.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="JupyterNotebook"
var_tags="${var_tags:-ai;dev-tools}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    python3 \
    python3-pip
  msg_ok "Installed Dependencies"

  INSTALL_DIR="/opt/jupyter"
  VENV_PYTHON="${INSTALL_DIR}/.venv/bin/python"
  VENV_JUPYTER="${INSTALL_DIR}/.venv/bin/jupyter"

  PYTHON_VERSION="3.12" setup_uv

  msg_info "Installing Jupyter Notebook"
  mkdir -p "$INSTALL_DIR"
  cd "$INSTALL_DIR" || exit
  $STD uv venv --clear .venv
  $STD "$VENV_PYTHON" -m ensurepip --upgrade
  $STD "$VENV_PYTHON" -m pip install --upgrade pip
  $STD "$VENV_PYTHON" -m pip install jupyter
  msg_ok "Installed Jupyter Notebook"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/jupyternotebook.service
[Unit]
Description=Jupyter Notebook Server
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${VENV_JUPYTER} notebook --ip=0.0.0.0 --port=8888 --allow-root
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now jupyternotebook
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8888${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  INSTALL_DIR="/opt/jupyter"
  VENV_PYTHON="${INSTALL_DIR}/.venv/bin/python"
  VENV_JUPYTER="${INSTALL_DIR}/.venv/bin/jupyter"
  SERVICE_FILE="/etc/systemd/system/jupyternotebook.service"

  if [[ ! -x "$VENV_JUPYTER" ]]; then
    msg_info "Migrating to uv venv"
    PYTHON_VERSION="3.12" setup_uv
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR" || exit
    $STD uv venv --clear .venv
    $STD "$VENV_PYTHON" -m ensurepip --upgrade
    $STD "$VENV_PYTHON" -m pip install --upgrade pip
    $STD "$VENV_PYTHON" -m pip install jupyter
    msg_ok "Migrated to uv and installed Jupyter"
  else
    msg_info "Updating Jupyter"
    $STD "$VENV_PYTHON" -m pip install --upgrade pip
    $STD "$VENV_PYTHON" -m pip install --upgrade jupyter
    msg_ok "Jupyter updated"
  fi

  if [[ -f "$SERVICE_FILE" && "$(grep ExecStart "$SERVICE_FILE")" != *".venv/bin/jupyter"* ]]; then
    msg_info "Updating systemd service to use .venv"
    cat << EOF > "$SERVICE_FILE"
[Unit]
Description=Jupyter Notebook Server
After=network.target
[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${VENV_JUPYTER} notebook --ip=0.0.0.0 --port=8888 --allow-root
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl restart jupyternotebook
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
