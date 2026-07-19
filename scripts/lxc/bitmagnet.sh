#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/bitmagnet-io/bitmagnet

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Bitmagnet"
var_tags="${var_tags:-os}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    iproute2 \
    gcc \
    musl-dev
  msg_ok "Installed Dependencies"

  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="bitmagnet" PG_DB_USER="bitmagnet" setup_postgresql_db
  setup_go

  fetch_and_deploy_gh_release "bitmagnet" "bitmagnet-io/bitmagnet" "tarball"
  RELEASE=$(cat ~/.bitmagnet)

  msg_info "Configuring bitmagnet"
  cd /opt/bitmagnet || exit
  $STD go build -ldflags "-s -w -X github.com/bitmagnet-io/bitmagnet/internal/version.GitTag=v${RELEASE}"
  chmod +x bitmagnet
  msg_ok "Configured bitmagnet"

  read -r -p "${TAB3}Enter your TMDB API key if you have one: " tmdbapikey

  cat << EOF > /etc/bitmagnet.env
POSTGRES_HOST=localhost
POSTGRES_USER=${PG_DB_USER}
POSTGRES_NAME=${PG_DB_NAME}
POSTGRES_PASSWORD=${PG_DB_PASS}
EOF

  if [ -z "$tmdbapikey" ]; then
    echo "TMDB_ENABLED=false" >> /etc/bitmagnet.env
  else
    echo "TMDB_API_KEY=$tmdbapikey" >> /etc/bitmagnet.env
  fi

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/bitmagnet-web.service
[Unit]
Description=bitmagnet Web GUI
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/bitmagnet
EnvironmentFile=/etc/bitmagnet.env
ExecStart=/opt/bitmagnet/bitmagnet worker run --all
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now bitmagnet-web
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3333${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/bitmagnet ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "bitmagnet" "bitmagnet-io/bitmagnet"; then
    msg_info "Stopping Service"
    systemctl stop bitmagnet-web
    msg_ok "Stopped Service"

    msg_info "Backing up data"
    rm -f /tmp/backup.sql
    $STD su - postgres -c "pg_dump \
      --column-inserts \
      --data-only \
      --on-conflict-do-nothing \
      --rows-per-insert=1000 \
      --table=metadata_sources \
      --table=content \
      --table=content_attributes \
      --table=content_collections \
      --table=content_collections_content \
      --table=torrent_sources \
      --table=torrents \
      --table=torrent_files \
      --table=torrent_hints \
      --table=torrent_contents \
      --table=torrent_tags \
      --table=torrents_torrent_sources \
      --table=key_values \
      bitmagnet \
      >/tmp/backup.sql"
    mv /tmp/backup.sql /opt/
    [ -f /opt/bitmagnet/.env ] && cp /opt/bitmagnet/.env /opt/
    [ -f /opt/bitmagnet/config.yml ] && cp /opt/bitmagnet/config.yml /opt/
    msg_ok "Data backed up"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "bitmagnet" "bitmagnet-io/bitmagnet" "tarball"
    [ -f "/opt/.env" ] && cp "/opt/.env" /opt/bitmagnet/
    [ -f "/opt/config.yml" ] && cp "/opt/config.yml" /opt/bitmagnet/

    msg_info "Configuring Bitmagnet"
    cd /opt/bitmagnet || exit
    VREL=v$(curl -fsSL https://api.github.com/repos/bitmagnet-io/bitmagnet/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
    $STD go build -ldflags "-s -w -X github.com/bitmagnet-io/bitmagnet/internal/version.GitTag=$VREL"
    chmod +x bitmagnet
    msg_ok "Configured Bitmagnet"

    msg_info "Starting Service"
    systemctl start bitmagnet-web
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
