#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://js.wiki/

# shellcheck disable=SC2034
APP="Wikijs"
var_tags="${var_tags:-wiki}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" NODE_MODULE="yarn,node-gyp" setup_nodejs
  PG_VERSION="17" setup_postgresql
  PG_DB_NAME="wiki" PG_DB_USER="wikijs_user" PG_DB_EXTENSIONS="pg_trgm" setup_postgresql_db
  fetch_and_deploy_gh_release "wikijs" "requarks/wiki" "prebuild" "latest" "/opt/wikijs" "wiki-js.tar.gz"

  msg_info "Configuring Wiki.js"
  mv /opt/wikijs/config.sample.yml /opt/wikijs/config.yml
  sed -i -E 's|^( *user: ).*|\1'"$PG_DB_USER"'|' /opt/wikijs/config.yml
  sed -i -E 's|^( *pass: ).*|\1'"$PG_DB_PASS"'|' /opt/wikijs/config.yml
  msg_ok "Configured Wiki.js"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/wikijs.service
[Unit]
Description=Wiki.js
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/node server
Restart=always
User=root
Environment=NODE_ENV=production
WorkingDirectory=/opt/wikijs

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now wikijs
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
  if [[ ! -d /opt/wikijs ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="24" NODE_MODULE="yarn,node-gyp" setup_nodejs

  if check_for_gh_release "wikijs" "requarks/wiki"; then
    msg_info "Verifying whether ${APP}' new release is v3.x+ and current install uses SQLite."
    SQLITE_INSTALL=$([ -f /opt/wikijs/db.sqlite ] && echo "true" || echo "false")
    if [[ "${SQLITE_INSTALL}" == "true" && "${CHECK_UPDATE_RELEASE}" =~ ^3.* ]]; then
      echo "SQLite is not supported in v3.x+, currently there is no update path availble."
      exit
    fi
    msg_ok "There is an update path available for ${APP}"

    msg_info "Stopping Service"
    systemctl stop wikijs
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    mkdir /opt/wikijs-backup
    $SQLITE_INSTALL && cp /opt/wikijs/db.sqlite /opt/wikijs-backup
    cp -R /opt/wikijs/{config.yml,/data} /opt/wikijs-backup
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "wikijs" "requarks/wiki" "prebuild" "latest" "/opt/wikijs" "wiki-js.tar.gz"

    msg_info "Restoring Data"
    cp -R /opt/wikijs-backup/* /opt/wikijs
    $SQLITE_INSTALL && $STD npm rebuild sqlite3
    rm -rf /opt/wikijs-backup
    msg_ok "Restored Data"

    msg_info "Starting Service"
    systemctl start wikijs
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
