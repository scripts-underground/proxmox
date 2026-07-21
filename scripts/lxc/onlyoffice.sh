#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.onlyoffice.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="ONLYOFFICE"
var_tags="${var_tags:-word;excel;powerpoint;pdf}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    nginx \
    rabbitmq-server \
    ca-certificates
  msg_ok "Installed Dependencies"

  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="onlyoffice" PG_DB_USER="onlyoffice_user" setup_postgresql_db

  msg_info "Adding ONLYOFFICE GPG Key"
  GPG_TMP="/tmp/onlyoffice.gpg"
  KEY_URL="https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE"
  TMP_KEY_CONTENT=$(mktemp)
  if curl -fsSL "$KEY_URL" -o "$TMP_KEY_CONTENT" && grep -q "BEGIN PGP PUBLIC KEY BLOCK" "$TMP_KEY_CONTENT"; then
    gpg --quiet --batch --yes --no-default-keyring --keyring "gnupg-ring:$GPG_TMP" --import "$TMP_KEY_CONTENT" > /dev/null 2>&1
    chmod 644 "$GPG_TMP"
    chown root:root "$GPG_TMP"
    mv "$GPG_TMP" /usr/share/keyrings/onlyoffice.gpg
    cat << EOF > /etc/apt/sources.list.d/onlyoffice.sources
Types: deb
URIs: https://download.onlyoffice.com/repo/debian
Suites: squeeze
Components: main
Signed-By: /usr/share/keyrings/onlyoffice.gpg
EOF
    $STD apt update
    msg_ok "GPG Key Added"
  else
    msg_error "Failed to download or verify GPG key from $KEY_URL"
    [[ -f "$TMP_KEY_CONTENT" ]] && rm -f "$TMP_KEY_CONTENT"
    exit 250
  fi
  rm -f "$TMP_KEY_CONTENT"

  msg_info "Preconfiguring ONLYOFFICE Debconf Settings"
  RMQ_USER=onlyoffice_rmq
  RMQ_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
  JWT_SECRET=$(openssl rand -hex 16)
  $STD rabbitmqctl add_user "$RMQ_USER" "$RMQ_PASS"
  $STD rabbitmqctl set_permissions -p / "$RMQ_USER" ".*" ".*" ".*"
  $STD rabbitmqctl set_user_tags "$RMQ_USER" administrator

  echo onlyoffice-documentserver onlyoffice/db-host string localhost | debconf-set-selections
  echo onlyoffice-documentserver onlyoffice/db-user string "$PG_DB_USER" | debconf-set-selections
  echo onlyoffice-documentserver onlyoffice/db-pwd password "$PG_DB_PASS" | debconf-set-selections
  echo onlyoffice-documentserver onlyoffice/db-name string "$PG_DB_NAME" | debconf-set-selections
  echo onlyoffice-documentserver onlyoffice/rabbitmq-host string localhost | debconf-set-selections
  echo onlyoffice-documentserver onlyoffice/rabbitmq-user string "$RMQ_USER" | debconf-set-selections
  echo onlyoffice-documentserver onlyoffice/rabbitmq-pwd password "$RMQ_PASS" | debconf-set-selections
  echo onlyoffice-documentserver onlyoffice/jwt-enabled boolean true | debconf-set-selections
  echo onlyoffice-documentserver onlyoffice/jwt-secret password "$JWT_SECRET" | debconf-set-selections

  cat << EOF > /root/onlyoffice.creds
ONLYOFFICE-Credentials
DB User: $PG_DB_USER
DB Password: $PG_DB_PASS
DB Name: $PG_DB_NAME
RMQ User: $RMQ_USER
RMQ Password: $RMQ_PASS
JWT Secret: $JWT_SECRET
EOF
  msg_ok "Debconf Preconfiguration Done"

  msg_info "Installing ttf-mscorefonts-installer"
  echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections
  $STD apt install -y ttf-mscorefonts-installer
  msg_ok "Installed Microsoft Core Fonts"

  msg_info "Installing ONLYOFFICE Docs"
  $STD apt install -y onlyoffice-documentserver
  msg_ok "ONLYOFFICE Docs Installed"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /var/www/onlyoffice ]]; then
    msg_error "No valid ${APP} installation found!"
    exit
  fi

  msg_info "Updating OnlyOffice Document Server"
  $STD apt update
  $STD apt -y --only-upgrade install onlyoffice-documentserver
  msg_ok "Updated OnlyOffice Document Server"

  if systemctl is-enabled --quiet onlyoffice-documentserver; then
    msg_info "Restarting OnlyOffice Document Server"
    $STD systemctl restart onlyoffice-documentserver
    msg_ok "OnlyOffice Document Server restarted"
  fi
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
