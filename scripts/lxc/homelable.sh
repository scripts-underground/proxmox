#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Pouzor/homelable

APP="Homelable"
var_tags="${var_tags:-monitoring;network;visualization}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    nmap \
    iputils-ping \
    caddy
  msg_ok "Installed Dependencies"

  UV_PYTHON="3.13" setup_uv
  NODE_VERSION="20" setup_nodejs
  fetch_and_deploy_gh_release "homelable" "Pouzor/homelable" "tarball" "latest" "/opt/homelable"

  msg_info "Setting up Python Backend"
  cd /opt/homelable/backend || exit
  $STD uv venv /opt/homelable/backend/.venv
  $STD uv pip install --python /opt/homelable/backend/.venv/bin/python -r requirements.txt
  msg_ok "Set up Python Backend"

  msg_info "Configuring Homelable"
  mkdir -p /opt/homelable/data
  SECRET_KEY=$(openssl rand -hex 32)
  BCRYPT_HASH=$(/opt/homelable/backend/.venv/bin/python -c "import bcrypt; print(bcrypt.hashpw(b'admin', bcrypt.gensalt()).decode())")
  cat << EOF > /opt/homelable/backend/.env
SECRET_KEY=${SECRET_KEY}
SQLITE_PATH=/opt/homelable/data/homelab.db
CORS_ORIGINS=["http://localhost:3000","http://${LOCAL_IP}:3000"]
AUTH_USERNAME=admin
AUTH_PASSWORD_HASH='${BCRYPT_HASH}'
SCANNER_RANGES=["192.168.1.0/24"]
STATUS_CHECKER_INTERVAL=60
EOF
  msg_ok "Configured Homelable"

  msg_info "Creating Password Reset Utility"
  cat << 'EOF' > /root/change_password.sh
#!/usr/bin/env bash

NEW_PASS=""

while [[ -z "$NEW_PASS" ]]; do
    read -s -p "Enter new password: " NEW_PASS
    echo ""
    if [[ -z "$NEW_PASS" ]]; then
        echo "Error: Password cannot be blank. Try again."
    fi
done

HASH=$(/opt/homelable/backend/.venv/bin/python -c "import bcrypt; print(bcrypt.hashpw('${NEW_PASS}'.encode(), bcrypt.gensalt()).decode())")

sed -i "s|^AUTH_PASSWORD_HASH=.*|AUTH_PASSWORD_HASH='${HASH}'|" /opt/homelable/backend/.env

systemctl restart homelable
echo "Password updated and service restarted successfully!"
EOF
  chmod +x /root/change_password.sh
  msg_ok "Created Password Reset Utility"

  msg_info "Building Frontend"
  cd /opt/homelable/frontend || exit
  $STD npm ci
  $STD npm run build
  msg_ok "Built Frontend"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/homelable.service
[Unit]
Description=Homelable Backend
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/homelable/backend
EnvironmentFile=/opt/homelable/backend/.env
ExecStart=/opt/homelable/backend/.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now homelable
  msg_ok "Created Service"

  msg_info "Configuring Caddy"
  cat << EOF > /etc/caddy/Caddyfile
:3000 {
    root * /opt/homelable/frontend/dist
    file_server

    @websocket path /api/v1/status/ws/*
    handle @websocket {
        reverse_proxy 127.0.0.1:8000
    }

    handle /ws/* {
        reverse_proxy 127.0.0.1:8000
    }

    handle /api/* {
        reverse_proxy 127.0.0.1:8000
    }

    handle {
        try_files {path} {path}.html /index.html
    }
}
EOF
  systemctl reload caddy
  msg_ok "Configured Caddy"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/homelable ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "homelable" "Pouzor/homelable"; then
    msg_info "Stopping Service"
    systemctl stop homelable
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration and Data"
    cp /opt/homelable/backend/.env /opt/homelable.env.bak
    cp -r /opt/homelable/data /opt/homelable_data_bak
    if [[ -f /opt/homelable/mcp/.env ]]; then
      cp -a /opt/homelable/mcp/.env /opt/homelable-mcp.env.bak
    fi
    msg_ok "Backed up Configuration and Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "homelable" "Pouzor/homelable" "tarball" "latest" "/opt/homelable"

    msg_info "Updating Python Dependencies"
    cd /opt/homelable/backend || exit
    $STD uv venv --clear /opt/homelable/backend/.venv
    $STD uv pip install --python /opt/homelable/backend/.venv/bin/python -r requirements.txt
    msg_ok "Updated Python Dependencies"

    msg_info "Rebuilding Frontend"
    cd /opt/homelable/frontend || exit
    $STD npm ci
    $STD npm run build
    msg_ok "Rebuilt Frontend"

    msg_info "Restoring Configuration and Data"
    cp /opt/homelable.env.bak /opt/homelable/backend/.env
    cp -r /opt/homelable_data_bak/. /opt/homelable/data/
    rm -f /opt/homelable.env.bak
    rm -rf /opt/homelable_data_bak
    msg_ok "Restored Configuration and Data"

    if [[ -f /opt/homelable-mcp.env.bak ]]; then
      msg_info "Restoring MCP Server"
      cp -a /opt/homelable-mcp.env.bak /opt/homelable/mcp/.env
      rm -f /opt/homelable-mcp.env.bak
      MCP_OWNER=$(stat -c '%U' /opt/homelable/mcp/.env)
      cd /opt/homelable/mcp || exit
      $STD uv venv --clear /opt/homelable/mcp/.venv
      $STD uv pip install --python /opt/homelable/mcp/.venv/bin/python -r requirements.txt
      chown -R "$MCP_OWNER":"$MCP_OWNER" /opt/homelable/mcp
      systemctl restart homelable-mcp
      msg_ok "Restored MCP Server"
    fi

    msg_info "Starting Service"
    systemctl start homelable
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
