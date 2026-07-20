#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://docmost.com/ | Github: https://github.com/docmost/docmost

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Docmost"
var_tags="${var_tags:-documents}"
var_cpu="${var_cpu:-3}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y redis make
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" NODE_MODULE="pnpm@$(curl -s https://raw.githubusercontent.com/docmost/docmost/main/package.json | jq -r '.packageManager | split("@")[1]')" setup_nodejs
  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="docmost_db" PG_DB_USER="docmost_user" setup_postgresql_db
  fetch_and_deploy_gh_release "docmost" "docmost/docmost" "tarball"

  msg_info "Configuring Docmost (Patience)"
  cd /opt/docmost || exit

  # Fix: Docmost EE (audit logs etc.) lives in a git submodule that is NOT
  # included in GitHub tarballs.  The community NoopAuditService exists but
  # is only exported by CoreModule – child modules such as UserModule cannot
  # resolve it.  Making CoreModule @Global() exposes the token app-wide.
  if [[ ! -f /opt/docmost/apps/server/src/ee/ee.module.ts ]] &&
    ! grep -q '@Global()' /opt/docmost/apps/server/src/core/core.module.ts 2> /dev/null; then
    sed -i '/^  Module,$/a\  Global,' /opt/docmost/apps/server/src/core/core.module.ts
    sed -i '/^@Module({$/i @Global()' /opt/docmost/apps/server/src/core/core.module.ts
  fi

  mv .env.example .env
  mkdir data
  sed -i -e "s|APP_SECRET=.*|APP_SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | cut -c1-32)|" \
    -e "s|DATABASE_URL=.*|DATABASE_URL=\"postgres://$PG_DB_USER:$PG_DB_PASS@localhost:5432/$PG_DB_NAME?schema=public\"|" \
    -e "s|FILE_UPLOAD_SIZE_LIMIT=.*|FILE_UPLOAD_SIZE_LIMIT=50mb|" \
    -e "s|DRAWIO_URL=.*|DRAWIO_URL=https://embed.diagrams.net|" \
    -e "s|DISABLE_TELEMETRY=.*|DISABLE_TELEMETRY=true|" \
    -e "s|APP_URL=.*|APP_URL=http://$LOCAL_IP:3000|" \
    -e "s|^STORAGE_DRIVER=azure|#STORAGE_DRIVER=azure|" \
    /opt/docmost/.env
  export NODE_OPTIONS="--max-old-space-size=2048"
  $STD pnpm install
  $STD pnpm build
  msg_ok "Configured Docmost"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/docmost.service
[Unit]
Description=Docmost Service
After=network.target postgresql.service

[Service]
WorkingDirectory=/opt/docmost
ExecStart=/usr/bin/pnpm start
Restart=always
EnvironmentFile=/opt/docmost/.env

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now docmost
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/docmost ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if ! command -v node > /dev/null || [[ "$(/usr/bin/env node -v | grep -oP '^v\K[0-9]+')" != "22" ]]; then
    NODE_VERSION="22" NODE_MODULE="pnpm@$(curl -s https://raw.githubusercontent.com/docmost/docmost/main/package.json | jq -r '.packageManager | split("@")[1]')" setup_nodejs
  fi
  export NODE_OPTIONS="--max_old_space_size=4096"

  if check_for_gh_release "docmost" "docmost/docmost"; then
    msg_info "Stopping Service"
    systemctl stop docmost
    msg_ok "Stopped Service"

    create_backup /opt/docmost/.env \
      /opt/docmost/data
    fetch_and_deploy_gh_release "docmost" "docmost/docmost" "tarball"
    restore_backup

    # Fix: Docmost EE (audit logs etc.) lives in a git submodule that is NOT
    # included in GitHub tarballs.
    if [[ ! -f /opt/docmost/apps/server/src/ee/ee.module.ts ]] &&
      ! grep -q '@Global()' /opt/docmost/apps/server/src/core/core.module.ts 2> /dev/null; then
      sed -i '/^  Module,$/a\  Global,' /opt/docmost/apps/server/src/core/core.module.ts
      sed -i '/^@Module({$/i @Global()' /opt/docmost/apps/server/src/core/core.module.ts
    fi

    msg_info "Configuring Docmost"
    cd /opt/docmost || exit
    $STD pnpm install --force
    $STD pnpm build
    msg_ok "Configured Docmost"

    msg_info "Starting Service"
    systemctl start docmost
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
