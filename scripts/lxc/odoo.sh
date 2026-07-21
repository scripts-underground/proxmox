#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/odoo/odoo

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Odoo"
var_tags="${var_tags:-erp}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    python3-lxml \
    wkhtmltopdf
  curl -fsSL --proto '=https' "https://archive.ubuntu.com/ubuntu/pool/universe/l/lxml-html-clean/python3-lxml-html-clean_0.1.1-1_all.deb" -o /opt/python3-lxml-html-clean.deb
  $STD dpkg -i /opt/python3-lxml-html-clean.deb
  rm -f /opt/python3-lxml-html-clean.deb
  msg_ok "Installed Dependencies"

  PG_VERSION="18" setup_postgresql

  RELEASE=$(curl -fsSL https://nightly.odoo.com/ | grep -oE 'href="[0-9]+\.[0-9]+/nightly"' | head -n1 | cut -d'"' -f2 | cut -d/ -f1)
  LATEST_VERSION=$(curl -fsSL "https://nightly.odoo.com/${RELEASE}/nightly/deb/" |
    grep -oP "odoo_${RELEASE}\.\d+_all\.deb" |
    sed -E "s/odoo_(${RELEASE}\.[0-9]+)_all\.deb/\1/" |
    sort -V |
    tail -n1)

  msg_info "Installing Odoo ${RELEASE}"
  curl -fsSL "https://nightly.odoo.com/${RELEASE}/nightly/deb/odoo_${RELEASE}.latest_all.deb" -o /opt/odoo.deb
  $STD apt install -y /opt/odoo.deb
  rm -f /opt/odoo.deb
  msg_ok "Installed Odoo ${RELEASE}"

  msg_info "Setting up PostgreSQL Database"
  DB_NAME="odoo"
  DB_USER="odoo_usr"
  DB_PASS="$(openssl rand -base64 18 | cut -c1-13)"
  $STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;"
  $STD sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
  $STD sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
  $STD sudo -u postgres psql -c "ALTER DATABASE $DB_NAME OWNER TO $DB_USER;"
  $STD sudo -u postgres psql -c "ALTER USER $DB_USER WITH SUPERUSER;"
  cat << EOF > ~/odoo.creds
Odoo-Credentials
Odoo Database User: $DB_USER
Odoo Database Password: $DB_PASS
Odoo Database Name: $DB_NAME
EOF
  msg_ok "Set up PostgreSQL Database"

  msg_info "Configuring Odoo"
  sed -i \
    -e "s|^;*db_host *=.*|db_host = localhost|" \
    -e "s|^;*db_port *=.*|db_port = 5432|" \
    -e "s|^;*db_user *=.*|db_user = $DB_USER|" \
    -e "s|^;*db_password *=.*|db_password = $DB_PASS|" \
    /etc/odoo/odoo.conf
  msg_ok "Configured Odoo"

  msg_info "Initializing Odoo"
  $STD sudo -u odoo odoo -c /etc/odoo/odoo.conf -d odoo -i base --stop-after-init
  echo "${LATEST_VERSION}" > /opt/${APP}_version.txt
  msg_ok "Initialized Odoo"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8069${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/odoo/odoo.conf ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  ensure_dependencies python3-lxml
  if ! [[ $(dpkg -s python3-lxml-html-clean 2> /dev/null) ]]; then
    curl -fsSL --proto '=https' "https://archive.ubuntu.com/ubuntu/pool/universe/l/lxml-html-clean/python3-lxml-html-clean_0.1.1-1_all.deb" -o /opt/python3-lxml-html-clean.deb
    $STD dpkg -i /opt/python3-lxml-html-clean.deb
    rm -f /opt/python3-lxml-html-clean.deb
  fi

  RELEASE=$(curl -fsSL https://nightly.odoo.com/ | grep -oE 'href="[0-9]+\.[0-9]+/nightly"' | head -n1 | cut -d'"' -f2 | cut -d/ -f1)
  LATEST_VERSION=$(curl -fsSL "https://nightly.odoo.com/${RELEASE}/nightly/deb/" |
    grep -oP "odoo_${RELEASE}\.\d+_all\.deb" |
    sed -E "s/odoo_(${RELEASE}\.[0-9]+)_all\.deb/\1/" |
    sort -V |
    tail -n1)

  if [[ "${LATEST_VERSION}" != "$(cat /opt/${APP}_version.txt)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
    msg_info "Stopping ${APP} service"
    systemctl stop odoo
    msg_ok "Stopped Service"

    msg_info "Updating ${APP} to ${LATEST_VERSION}"
    curl -fsSL "https://nightly.odoo.com/${RELEASE}/nightly/deb/odoo_${RELEASE}.latest_all.deb" -o /opt/odoo.deb
    $STD apt install -y /opt/odoo.deb
    rm -f /opt/odoo.deb
    echo "$LATEST_VERSION" > /opt/${APP}_version.txt
    msg_ok "Updated ${APP} to ${LATEST_VERSION}"

    msg_info "Starting Service"
    systemctl start odoo
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. ${APP} is already at ${LATEST_VERSION}"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
