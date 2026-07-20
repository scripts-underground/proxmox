#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: stout01
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/BerriAI/litellm

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="LiteLLM"
var_tags="${var_tags:-ai;interface}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    python3-dev
  msg_ok "Installed Dependencies"

  PG_VERSION="17" setup_postgresql
  PG_DB_NAME="litellm_db" PG_DB_USER="litellm" setup_postgresql_db
  PYTHON_VERSION="3.13" USE_UVX="YES" setup_uv

  msg_info "Setting up Virtual Environment"
  mkdir -p /opt/litellm
  cd /opt/litellm || exit
  $STD uv venv --clear /opt/litellm/.venv
  $STD /opt/litellm/.venv/bin/python -m ensurepip --upgrade
  $STD /opt/litellm/.venv/bin/python -m pip install --upgrade pip
  $STD /opt/litellm/.venv/bin/python -m pip install litellm[proxy] prisma
  $STD /opt/litellm/.venv/bin/prisma generate
  msg_ok "Installed LiteLLM"

  msg_info "Configuring LiteLLM"
  cat << EOF > /opt/litellm/litellm.yaml
general_settings:
  master_key: sk-1234
  database_url: postgresql://$PG_DB_USER:$PG_DB_PASS@127.0.0.1:5432/$PG_DB_NAME
  store_model_in_db: true
EOF
  $STD /opt/litellm/.venv/bin/litellm --config /opt/litellm/litellm.yaml --use_prisma_db_push --skip_server_startup
  msg_ok "Configured LiteLLM"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/litellm.service
[Unit]
Description=LiteLLM

[Service]
Type=simple
ExecStart=/opt/litellm/.venv/bin/litellm --config /opt/litellm/litellm.yaml
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now litellm
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:4000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/systemd/system/litellm.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop litellm
  msg_ok "Stopped Service"

  VENV_PATH="/opt/litellm/.venv"
  PYTHON_VERSION="3.13" USE_UVX="YES" setup_uv

  msg_info "Updating LiteLLM"
  $STD "$VENV_PATH/bin/python" -m pip install --upgrade litellm[proxy] prisma
  $STD "$VENV_PATH/bin/prisma" generate
  msg_ok "LiteLLM updated"

  msg_info "Updating DB Schema"
  $STD /opt/litellm/.venv/bin/litellm --config /opt/litellm/litellm.yaml --use_prisma_db_push --skip_server_startup
  msg_ok "DB Schema Updated"

  msg_info "Updating Service"
  sed -i 's|ExecStart=uv --directory=/opt/litellm run litellm|ExecStart=/opt/litellm/.venv/bin/litellm|' /etc/systemd/system/litellm.service
  systemctl daemon-reload
  msg_ok "Updated Service"

  msg_info "Starting Service"
  systemctl start litellm
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
