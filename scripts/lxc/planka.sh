#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2155,SC2046
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tremor021
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/plankanban/planka

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="PLANKA"
var_tags="${var_tags:-kanban;todo}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    unzip \
    build-essential \
    python3-venv
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" setup_nodejs
  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="planka" PG_DB_USER="planka" setup_postgresql_db

  fetch_and_deploy_gh_release "planka" "plankanban/planka" "prebuild" "latest" "/opt/planka" "planka-prebuild.zip"

  msg_info "Configuring PlanKa"
  SECRET_KEY=$(openssl rand -hex 64)
  cd /opt/planka || exit
  $STD npm install
  cp .env.sample .env
  sed -i "s#http://localhost:1337#http://$LOCAL_IP:1337#g" /opt/planka/.env
  sed -i "s#postgres@localhost#planka:$PG_DB_PASS@localhost#g" /opt/planka/.env
  sed -i "s#notsecretkey#$SECRET_KEY#g" /opt/planka/.env
  mkdir -p /opt/planka/data/protected/{favicons,user-avatars,background-images} /opt/planka/data/private/attachments
  $STD npm run db:init
  msg_ok "Configured PlanKa"

  msg_info "Creating Admin User"
  ADMIN_EMAIL="admin@planka.local"
  ADMIN_PASSWORD=$(openssl rand -base64 12)
  ADMIN_NAME="Administrator"
  ADMIN_USERNAME="admin"
  cat << EOF >> .env
# Temporary admin user creation settings
DEFAULT_ADMIN_EMAIL=$ADMIN_EMAIL
DEFAULT_ADMIN_PASSWORD=$ADMIN_PASSWORD
DEFAULT_ADMIN_NAME=$ADMIN_NAME
DEFAULT_ADMIN_USERNAME=$ADMIN_USERNAME
EOF
  $STD npm run db:seed
  sed -i '/# Temporary admin user creation settings/,$d' .env
  {
    echo "PLANKA Admin Credentials"
    echo "Admin Email: $ADMIN_EMAIL"
    echo "Admin Password: $ADMIN_PASSWORD"
    echo "Admin Name: $ADMIN_NAME"
    echo "Admin Username: $ADMIN_USERNAME"
  } > ~/planka.creds
  msg_ok "Created Admin User"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/planka.service
[Unit]
Description=PlanKa Service
After=network.target postgresql.service
Requires=postgresql.service

[Service]
WorkingDirectory=/opt/planka
ExecStart=/usr/bin/npm start --prod
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now planka
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:1337${CL}"
  echo -e "${INFO}${YW}Credentials stored in: ~/planka.creds${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/systemd/system/planka.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "planka" "plankanban/planka"; then
    msg_info "Stopping Service"
    systemctl stop planka
    msg_ok "Stopped Service"

    msg_info "Backing up data"
    BK="/opt/planka/.backup"
    mkdir -p "$BK"/{favicons,user-avatars,background-images,attachments}
    [ -f /opt/planka/.env ] && mv /opt/planka/.env "$BK"/
    if [ -d /opt/planka/data/protected ]; then
      [ -d /opt/planka/data/protected/favicons ] && cp -a /opt/planka/data/protected/favicons/. "$BK/favicons/"
      [ -d /opt/planka/data/protected/user-avatars ] && cp -a /opt/planka/data/protected/user-avatars/. "$BK/user-avatars/"
      [ -d /opt/planka/data/protected/background-images ] && cp -a /opt/planka/data/protected/background-images/. "$BK/background-images/"
      [ -d /opt/planka/data/private/attachments ] && cp -a /opt/planka/data/private/attachments/. "$BK/attachments/"
    else
      [ -d /opt/planka/public/favicons ] && cp -a /opt/planka/public/favicons/. "$BK/favicons/"
      [ -d /opt/planka/public/user-avatars ] && cp -a /opt/planka/public/user-avatars/. "$BK/user-avatars/"
      [ -d /opt/planka/public/background-images ] && cp -a /opt/planka/public/background-images/. "$BK/background-images/"
      [ -d /opt/planka/private/attachments ] && cp -a /opt/planka/private/attachments/. "$BK/attachments/"
    fi
    rm -rf /opt/planka
    msg_ok "Backed up data"

    fetch_and_deploy_gh_release "planka" "plankanban/planka" "prebuild" "latest" "/opt/planka" "planka-prebuild.zip"

    msg_info "Update Frontend"
    cd /opt/planka || exit
    $STD npm install
    msg_ok "Updated Frontend"

    msg_info "Restoring data"
    [ -f "$BK/.env" ] && mv "$BK/.env" /opt/planka/.env
    mkdir -p /opt/planka/data/protected/{favicons,user-avatars,background-images} /opt/planka/data/private/attachments
    [ -d "$BK/favicons" ] && cp -a "$BK/favicons/." /opt/planka/data/protected/favicons/
    [ -d "$BK/user-avatars" ] && cp -a "$BK/user-avatars/." /opt/planka/data/protected/user-avatars/
    [ -d "$BK/background-images" ] && cp -a "$BK/background-images/." /opt/planka/data/protected/background-images/
    [ -d "$BK/attachments" ] && cp -a "$BK/attachments/." /opt/planka/data/private/attachments/
    rm -rf "$BK"
    msg_ok "Restored data"

    msg_info "Migrate Database"
    cd /opt/planka || exit
    $STD npm run db:upgrade
    $STD npm run db:migrate
    msg_ok "Migrated Database"

    msg_info "Starting Service"
    systemctl start planka
    msg_ok "Started Service"
    msg_ok "Updated Successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
