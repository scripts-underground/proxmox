#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/databasus/databasus

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Databasus"
var_tags="${var_tags:-backup;postgresql;database}"
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
    gnupg \
    lsb-release \
    mariadb-client
  msg_ok "Installed Dependencies"

  PG_VERSION="17" setup_postgresql
  setup_go
  NODE_VERSION="24" NODE_MODULE="corepack" setup_nodejs

  msg_info "Installing MongoDB Database Tools"
  ARCH=$(uname -m)
  [[ "$ARCH" == "aarch64" ]] && MONGO_ARCH="arm64" || MONGO_ARCH="x86_64"
  MONGO_DIST="debian12"
  [[ "$MONGO_ARCH" == "arm64" ]] && MONGO_DIST="ubuntu2204"
  $STD apt install -y wget
  wget -q "https://fastdl.mongodb.org/tools/db/mongodb-database-tools-${MONGO_DIST}-${MONGO_ARCH}-100.16.1.deb" -O /tmp/mongodb-tools.deb
  $STD dpkg -i /tmp/mongodb-tools.deb || true
  $STD apt install -f -y
  rm -f /tmp/mongodb-tools.deb
  msg_ok "Installed MongoDB Database Tools"

  CLEAN_INSTALL=1 fetch_and_deploy_gh_release "databasus" "databasus/databasus" "tarball" "latest" "/opt/databasus"

  msg_info "Building Databasus"
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  cd /opt/databasus/frontend || exit
  $STD corepack prepare pnpm@latest --activate
  $STD pnpm install --frozen-lockfile
  $STD pnpm run build
  cd /opt/databasus/backend || exit
  $STD go mod download
  $STD /root/go/bin/swag init -g cmd/main.go -o swagger
  ARCH=$(uname -m)
  [[ "$ARCH" == "aarch64" ]] && GOARCH="arm64" || GOARCH="amd64"
  $STD env CGO_ENABLED=0 GOOS=linux GOARCH="$GOARCH" go build -o databasus ./cmd
  mv /opt/databasus/backend/databasus /opt/databasus/databasus
  mkdir -p /opt/databasus/ui/build
  cp -r /opt/databasus/frontend/dist/* /opt/databasus/ui/build/
  cp -r /opt/databasus/backend/migrations /opt/databasus/
  chown -R postgres:postgres /opt/databasus
  msg_ok "Built Databasus"

  msg_info "Creating Database Client Symlinks"
  for v in 12 13 14 15 16 18; do
    ln -sf /usr/lib/postgresql/17 /usr/lib/postgresql/"$v"
  done
  mkdir -p /usr/local/mariadb-{10.6,12.1}/bin /usr/local/mysql-{5.7,8.0,8.4,9}/bin /usr/local/mongodb-database-tools/bin
  [[ -f /usr/bin/mongodump ]] && ln -sf /usr/bin/mongodump /usr/local/mongodb-database-tools/bin/mongodump
  [[ -f /usr/bin/mongorestore ]] && ln -sf /usr/bin/mongorestore /usr/local/mongodb-database-tools/bin/mongorestore
  for dir in /usr/local/mariadb-{10.6,12.1}/bin; do
    ln -sf /usr/bin/mariadb-dump "$dir/mariadb-dump"
    ln -sf /usr/bin/mariadb "$dir/mariadb"
  done
  for dir in /usr/local/mysql-{5.7,8.0,8.4,9}/bin; do
    ln -sf /usr/bin/mariadb-dump "$dir/mysqldump"
    ln -sf /usr/bin/mariadb "$dir/mysql"
  done
  msg_ok "Created Database Client Symlinks"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/databasus.service
[Unit]
Description=Databasus
After=network.target

[Service]
Type=simple
User=postgres
ExecStart=/opt/databasus/databasus
EnvironmentFile=/.env
WorkingDirectory=/opt/databasus
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now databasus
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:4005${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/databasus/databasus ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="24" NODE_MODULE="corepack" setup_nodejs

  if check_for_gh_release "databasus" "databasus/databasus"; then
    msg_info "Stopping Databasus"
    $STD systemctl stop databasus
    msg_ok "Stopped Databasus"

    create_backup /opt/databasus/.env

    msg_info "Ensuring Database Clients"
    for v in 12 13 14 15 16 18; do
      ln -sf /usr/lib/postgresql/17 /usr/lib/postgresql/$v
    done
    if ! command -v mongodump &> /dev/null; then
      ARCH=$(uname -m)
      [[ "$ARCH" == "aarch64" ]] && MONGO_ARCH="arm64" || MONGO_ARCH="x86_64"
      [[ "$(get_os_info id)" == "ubuntu" ]] && MONGO_DIST="ubuntu2204" || MONGO_DIST="debian12"
      [[ "$MONGO_ARCH" == "arm64" ]] && MONGO_DIST="ubuntu2204"
      wget -q "https://fastdl.mongodb.org/tools/db/mongodb-database-tools-${MONGO_DIST}-${MONGO_ARCH}-100.16.1.deb" -O /tmp/mongodb-tools.deb
      $STD dpkg -i /tmp/mongodb-tools.deb || true
      $STD apt install -f -y
      rm -f /tmp/mongodb-tools.deb
    fi
    ensure_dependencies mariadb-client
    mkdir -p /usr/local/mariadb-{10.6,12.1}/bin /usr/local/mysql-{5.7,8.0,8.4,9}/bin /usr/local/mongodb-database-tools/bin
    [[ -f /usr/bin/mongodump ]] && ln -sf /usr/bin/mongodump /usr/local/mongodb-database-tools/bin/mongodump
    [[ -f /usr/bin/mongorestore ]] && ln -sf /usr/bin/mongorestore /usr/local/mongodb-database-tools/bin/mongorestore
    for dir in /usr/local/mariadb-{10.6,12.1}/bin; do
      ln -sf /usr/bin/mariadb-dump "$dir/mariadb-dump"
      ln -sf /usr/bin/mariadb "$dir/mariadb"
    done
    for dir in /usr/local/mysql-{5.7,8.0,8.4,9}/bin; do
      ln -sf /usr/bin/mariadb-dump "$dir/mysqldump"
      ln -sf /usr/bin/mariadb "$dir/mysql"
    done
    msg_ok "Ensured Database Clients"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "databasus" "databasus/databasus" "tarball" "latest" "/opt/databasus"

    msg_info "Updating Databasus"
    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
    cd /opt/databasus/frontend || exit
    $STD corepack prepare pnpm@latest --activate
    $STD pnpm install --frozen-lockfile
    $STD pnpm run build
    cd /opt/databasus/backend || exit
    $STD go mod download
    $STD /root/go/bin/swag init -g cmd/main.go -o swagger
    ARCH=$(uname -m)
    [[ "$ARCH" == "aarch64" ]] && GOARCH="arm64" || GOARCH="amd64"
    $STD env CGO_ENABLED=0 GOOS=linux GOARCH="$GOARCH" go build -o databasus ./cmd
    mv /opt/databasus/backend/databasus /opt/databasus/databasus
    mkdir -p /opt/databasus/ui/build
    cp -r /opt/databasus/frontend/dist/* /opt/databasus/ui/build/
    cp -r /opt/databasus/backend/migrations /opt/databasus/
    chown -R postgres:postgres /opt/databasus
    msg_ok "Updated Databasus"

    restore_backup

    if ! grep -q "EnvironmentFile=/.env" /etc/systemd/system/databasus.service; then
      msg_info "Updating Service"
      sed -i 's|EnvironmentFile=.*|EnvironmentFile=/.env|' /etc/systemd/system/databasus.service
      $STD systemctl daemon-reload
      msg_ok "Updated Service"
    fi

    msg_info "Starting Databasus"
    $STD systemctl start databasus
    msg_ok "Started Databasus"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
