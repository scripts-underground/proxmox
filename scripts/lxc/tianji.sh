#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2155,SC2046
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/msgbyte/tianji

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Tianji"
var_tags="${var_tags:-monitoring}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-12}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    python3 \
    cmake \
    build-essential \
    git
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" NODE_MODULE="pnpm@$(curl -s https://raw.githubusercontent.com/msgbyte/tianji/master/package.json | jq -r '.packageManager | split("@")[1]')" setup_nodejs
  PG_VERSION="17" setup_postgresql
  PG_DB_NAME="tianji_db" PG_DB_USER="tianji" setup_postgresql_db
  PYTHON_VERSION="3.13" setup_uv
  fetch_and_deploy_gh_release "tianji" "msgbyte/tianji" "tarball"
  TIANJI_SECRET=$(openssl rand -base64 256 | tr -dc 'A-Za-z' | head -c 64)
  echo "Tianji Secret: $TIANJI_SECRET" >> ~/tianji.creds

  msg_info "Setting up Tianji"
  cd /opt/tianji || exit
  $STD pnpm install --filter @tianji/client... --config.dedupe-peer-dependents=false --frozen-lockfile
  $STD pnpm build:static
  $STD pnpm install --filter @tianji/server... --config.dedupe-peer-dependents=false
  mkdir -p ./src/server/public
  cp -r ./geo ./src/server/public
  $STD pnpm build:server
  cat << EOF > /opt/tianji/src/server/.env
DATABASE_URL="postgresql://$PG_DB_USER:$PG_DB_PASS@localhost:5432/$PG_DB_NAME?schema=public"
OPENAI_API_KEY=""
JWT_SECRET="$TIANJI_SECRET"
EOF
  cd /opt/tianji/src/server || exit
  $STD pnpm db:migrate:apply
  rm -rf /opt/tianji/src/client
  rm -rf /opt/tianji/website
  rm -rf /opt/tianji/reporter
  msg_ok "Setup Tianji"

  msg_info "Setting up AppRise"
  $STD uv pip install apprise cryptography --system
  msg_ok "Setup AppRise"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/tianji.service
[Unit]
Description=Tianji Server
After=network.target

[Service]
ExecStart=/usr/bin/node /opt/tianji/src/server/dist/src/server/main.js
WorkingDirectory=/opt/tianji/src/server
Restart=always
RestartSec=10
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now tianji
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:12345${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/tianji ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  setup_uv
  if check_for_gh_release "tianji" "msgbyte/tianji"; then
    NODE_VERSION="22" NODE_MODULE="pnpm@$(curl -s https://raw.githubusercontent.com/msgbyte/tianji/master/package.json | jq -r '.packageManager | split("@")[1]')" setup_nodejs

    msg_info "Stopping Service"
    systemctl stop tianji
    msg_ok "Stopped Service"

    msg_info "Backing up data"
    cp /opt/tianji/src/server/.env /opt/.env
    mv /opt/tianji /opt/tianji_bak
    msg_ok "Backed up data"

    fetch_and_deploy_gh_release "tianji" "msgbyte/tianji" "tarball"

    msg_info "Updating Tianji"
    cd /opt/tianji || exit
    export NODE_OPTIONS="--max_old_space_size=4096"
    $STD pnpm install --filter @tianji/client... --config.dedupe-peer-dependents=false --frozen-lockfile
    $STD pnpm build:static
    $STD pnpm install --filter @tianji/server... --config.dedupe-peer-dependents=false
    mkdir -p ./src/server/public
    cp -r ./geo ./src/server/public
    $STD pnpm build:server
    mv /opt/.env /opt/tianji/src/server/.env
    cd src/server || exit
    $STD pnpm db:migrate:apply
    rm -rf /opt/tianji_bak
    rm -rf /opt/tianji/src/client
    rm -rf /opt/tianji/website
    rm -rf /opt/tianji/reporter
    msg_ok "Updated Tianji"

    msg_info "Updating AppRise"
    $STD uv pip install apprise cryptography --system
    msg_ok "Updated AppRise"

    msg_info "Starting Service"
    systemctl start tianji
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
