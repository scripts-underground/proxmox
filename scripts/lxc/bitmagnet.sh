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

  local tmdbapikey="" tmdb_config="TMDB_ENABLED=false" configuration status
  read -r -p "${TAB3}Enter your TMDB API key if you have one: " tmdbapikey || true
  [[ -z "$tmdbapikey" ]] || tmdb_config="TMDB_API_KEY=$tmdbapikey"
  configuration=$(mktemp /etc/.bitmagnet.env.XXXXXXXX)
  chown root:root "$configuration"
  chmod 0600 "$configuration"
  if printf '%s\n' "POSTGRES_HOST=localhost" "POSTGRES_USER=${PG_DB_USER}" \
    "POSTGRES_NAME=${PG_DB_NAME}" "POSTGRES_PASSWORD=${PG_DB_PASS}" "$tmdb_config" > "$configuration"; then
    :
  else
    status=$?
    rm -f -- "$configuration"
    return "$status"
  fi
  mv -T -- "$configuration" /etc/bitmagnet.env

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
    exit 1
  fi
  if [[ ! -f /etc/bitmagnet.env ]]; then
    msg_error "Missing /etc/bitmagnet.env; restore the existing database configuration before updating."
    exit 1
  fi
  # PID 1 reads EnvironmentFile; harden in place without rewriting secrets.
  chown root:root /etc/bitmagnet.env
  chmod 0600 /etc/bitmagnet.env
  if check_for_gh_release "bitmagnet" "bitmagnet-io/bitmagnet"; then
    msg_info "Stopping Service"
    systemctl stop bitmagnet-web
    msg_ok "Stopped Service"

    msg_info "Backing up data"
    local backup_file status
    backup_file=$(mktemp /opt/.bitmagnet-backup.XXXXXXXX)
    # Keep dump stdout out of STD's log redirection, and off RAM-backed /tmp.
    if runuser -u postgres -- pg_dump \
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
      bitmagnet > "$backup_file" && mv -T -- "$backup_file" /opt/backup.sql; then
      :
    else
      status=$?
      rm -f -- "$backup_file"
      return "$status"
    fi
    msg_ok "Data backed up"

    local -a CLEAN_INSTALL_KEEP_PATHS=("${CLEAN_INSTALL_KEEP_PATHS[@]}" ".env" "config.yml")
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "bitmagnet" "bitmagnet-io/bitmagnet" "tarball" "$CHECK_UPDATE_RELEASE"

    msg_info "Configuring Bitmagnet"
    cd /opt/bitmagnet || exit
    $STD go build -ldflags "-s -w -X github.com/bitmagnet-io/bitmagnet/internal/version.GitTag=$CHECK_UPDATE_RELEASE"
    chmod +x bitmagnet
    msg_ok "Configured Bitmagnet"

    msg_info "Starting Service"
    systemctl start bitmagnet-web
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  else
    local status=$?
    [[ "$status" == 1 ]] || return "$status"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc") --script-id "bitmagnet" -- "$@"
