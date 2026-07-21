#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Kaedon Cleland-Host (dracentis)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://mattermost.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Mattermost"
var_tags="${var_tags:-collaboration}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  PG_VERSION="16" setup_postgresql

  msg_info "Setting up PostgreSQL"
  DB_NAME=mattermost
  DB_USER=mmuser
  DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  $STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;"
  $STD sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
  $STD sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME to $DB_USER;"
  $STD sudo -u postgres psql -c "ALTER DATABASE $DB_NAME OWNER TO $DB_USER;"
  $STD sudo -u postgres psql -c "GRANT USAGE, CREATE ON SCHEMA PUBLIC TO $DB_USER;"
  cat << EOF > ~/mattermost.creds
Mattermost Credentials
Database User: $DB_USER
Database Password: $DB_PASS
Database Name: $DB_NAME
EOF
  msg_ok "Set up PostgreSQL"

  msg_info "Installing Mattermost"
  curl -fsSL -o /usr/share/keyrings/mattermost-archive-keyring.gpg https://deb.packages.mattermost.com/pubkey.gpg
  sh -c 'curl -fsSL https://deb.packages.mattermost.com/repo-setup.sh | sudo bash -s mattermost' > /dev/null
  $STD apt update
  $STD apt install -y mattermost
  $STD install -C -m 600 -o mattermost -g mattermost /opt/mattermost/config/config.defaults.json /opt/mattermost/config/config.json
  sed -i -e "/DataSource/c\   \"DataSource\": \"postgres://$DB_USER:$DB_PASS@localhost:5432/$DB_NAME?sslmode=disable&connect_timeout=10\"," \
    -e "/SiteURL/c\   \"SiteURL\": \"http://$LOCAL_IP:8065\"," /opt/mattermost/config/config.json
  systemctl enable -q --now mattermost
  msg_ok "Installed Mattermost"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8065${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/apt/sources.list.d/mattermost.list ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP} LXC"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
