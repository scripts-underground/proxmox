#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/bitmagnet-io/bitmagnet

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-bitmagnet"
var_tags="${var_tags:-alpine;torrent}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-3}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing dependencies"
  $STD apk add --no-cache \
    gcc \
    musl-dev \
    git \
    iproute2-ss \
    sudo
  $STD apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community go
  msg_ok "Installed dependencies"

  msg_info "Installing PostgreSQL"
  $STD apk add --no-cache \
    postgresql16 \
    postgresql16-contrib \
    postgresql16-openrc
  $STD rc-update add postgresql
  $STD rc-service postgresql start
  msg_ok "Installed PostgreSQL"

  RELEASE=$(curl -fsSL https://api.github.com/repos/bitmagnet-io/bitmagnet/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')

  msg_info "Installing bitmagnet v${RELEASE}"
  mkdir -p /opt/bitmagnet
  temp_file=$(mktemp)
  curl -fsSL "https://github.com/bitmagnet-io/bitmagnet/archive/refs/tags/v${RELEASE}.tar.gz" -o "$temp_file"
  tar zxf "$temp_file" --strip-components=1 -C /opt/bitmagnet
  cd /opt/bitmagnet || exit
  VREL=v$RELEASE
  $STD go build -ldflags "-s -w -X github.com/bitmagnet-io/bitmagnet/internal/version.GitTag=$VREL"
  chmod +x bitmagnet
  $STD su - postgres -c "psql -c 'CREATE DATABASE bitmagnet;'"
  echo "${RELEASE}" > /opt/bitmagnet_version.txt
  msg_ok "Installed bitmagnet v${RELEASE}"

  read -rp "${TAB3}Enter your TMDB API key if you have one: " tmdbapikey

  msg_info "Enabling bitmagnet Service"
  cat << EOF > /etc/init.d/bitmagnet
#!/sbin/openrc-run
description="bitmagnet Service"
directory="/opt/bitmagnet"
command="/opt/bitmagnet/bitmagnet"
command_args="worker run --all"
command_background="true"
command_user="root"
pidfile="/var/run/bitmagnet.pid"

depend() {
    use net
}

start_pre() {
    export TMDB_API_KEY="$tmdbapikey"
}
EOF
  chmod +x /etc/init.d/bitmagnet
  $STD rc-update add bitmagnet default
  msg_ok "Enabled bitmagnet Service"

  msg_info "Starting bitmagnet"
  $STD service bitmagnet start
  msg_ok "Started bitmagnet"

  msg_info "Cleaning up"
  rm -f "$temp_file"
  $STD apk cache clean
  msg_ok "Cleaned"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3333${CL}"
}

function update_script() {
  header_info
  if [[ ! -d /opt/bitmagnet ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  RELEASE=$(curl -fsSL https://api.github.com/repos/bitmagnet-io/bitmagnet/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  if [ "${RELEASE}" != "$(cat /opt/bitmagnet_version.txt)" ] || [ ! -f /opt/bitmagnet_version.txt ]; then
    msg_info "Backing up database"
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
    msg_ok "Database backed up"

    msg_info "Updating ${APP} from $(cat /opt/bitmagnet_version.txt) to ${RELEASE}"
    $STD apk -U upgrade
    $STD service bitmagnet stop
    [ -f /opt/bitmagnet/.env ] && cp /opt/bitmagnet/.env /opt/
    [ -f /opt/bitmagnet/config.yml ] && cp /opt/bitmagnet/config.yml /opt/
    rm -rf /opt/bitmagnet/*
    temp_file=$(mktemp)
    curl -fsSL "https://github.com/bitmagnet-io/bitmagnet/archive/refs/tags/v${RELEASE}.tar.gz" -o "$temp_file"
    tar zxf "$temp_file" --strip-components=1 -C /opt/bitmagnet
    cd /opt/bitmagnet || exit
    VREL=v$RELEASE
    $STD go build -ldflags "-s -w -X github.com/bitmagnet-io/bitmagnet/internal/version.GitTag=$VREL"
    chmod +x bitmagnet
    [ -f "/opt/.env" ] && cp "/opt/.env" /opt/bitmagnet/
    [ -f "/opt/config.yml" ] && cp "/opt/config.yml" /opt/bitmagnet/
    rm -f "$temp_file"
    echo "${RELEASE}" > /opt/bitmagnet_version.txt
    $STD service bitmagnet start
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE}"
  fi
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
