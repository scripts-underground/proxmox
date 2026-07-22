#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: dave-yap (dave-yap)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://zitadel.com/ | Github: https://github.com/zitadel/zitadel

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Zitadel"
var_tags="${var_tags:-identity-provider}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies (Patience)"
  $STD apt install -y ca-certificates lsof
  msg_ok "Installed Dependencies"

  PG_VERSION="17" setup_postgresql

  msg_info "Installing PostgreSQL"
  DB_NAME="zitadel"
  DB_USER="zitadel"
  DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
  DB_ADMIN_USER="root"
  DB_ADMIN_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
  systemctl start postgresql
  $STD sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
  $STD sudo -u postgres psql -c "CREATE USER $DB_ADMIN_USER WITH PASSWORD '$DB_ADMIN_PASS' SUPERUSER;"
  $STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_ADMIN_USER;"
  cat << EOF > ~/zitadel.creds
Application Credentials
DB_NAME: $DB_NAME
DB_USER: $DB_USER
DB_PASS: $DB_PASS
DB_ADMIN_USER: $DB_ADMIN_USER
DB_ADMIN_PASS: $DB_ADMIN_PASS
EOF
  msg_ok "Installed PostgreSQL"

  fetch_and_deploy_gh_release "zitadel" "zitadel/zitadel" "prebuild" "latest" "/usr/local/bin" "zitadel-linux-$(get_system_arch).tar.gz"

  msg_info "Setting up Zitadel Environments"
  mkdir -p /opt/zitadel
  echo "/opt/zitadel/config.yaml" > "/opt/zitadel/.config"
  head -c 32 < <(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9') > "/opt/zitadel/.masterkey"
  cat << EOF > ~/zitadel.creds
Config location: $(cat "/opt/zitadel/.config")
Masterkey: $(cat "/opt/zitadel/.masterkey")
EOF
  cat << EOF > /opt/zitadel/config.yaml
Port: 8080
ExternalPort: 8080
ExternalDomain: localhost
ExternalSecure: false
TLS:
  Enabled: false
  KeyPath: ""
  Key: ""
  CertPath: ""
  Cert: ""

Database:
  postgres:
    Host: localhost
    Port: 5432
    Database: ${DB_NAME}
    User:
      Username: ${DB_USER}
      Password: ${DB_PASS}
      SSL:
        Mode: disable
        RootCert: ""
        Cert: ""
        Key: ""
    Admin:
      Username: ${DB_ADMIN_USER}
      Password: ${DB_ADMIN_PASS}
      SSL:
        Mode: disable
        RootCert: ""
        Cert: ""
        Key: ""
DefaultInstance:
  Features:
    LoginV2:
      Required: false
EOF
  msg_ok "Installed Zitadel Environments"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/zitadel.service
[Unit]
Description=ZITADEL Identity Server
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=zitadel
Group=zitadel
ExecStart=/usr/local/bin/zitadel start --masterkeyFile "/opt/zitadel/.masterkey" --config "/opt/zitadel/config.yaml"
Restart=always
RestartSec=5
TimeoutStartSec=0

# Security Hardening options
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now zitadel
  msg_ok "Created Services"

  msg_info "Zitadel initial setup"
  zitadel start-from-init --masterkeyFile /opt/zitadel/.masterkey --config /opt/zitadel/config.yaml &> /dev/null &
  sleep 60
  kill "$(lsof -i | awk '/zitadel/ {print $2}' | head -n1)"
  useradd zitadel
  msg_ok "Zitadel initialized"

  msg_info "Set ExternalDomain to current IP and restart Zitadel"
  sed -i "0,/localhost/s/localhost/${LOCAL_IP}/" /opt/zitadel/config.yaml
  systemctl stop -q zitadel
  $STD zitadel setup --masterkeyFile /opt/zitadel/.masterkey --config /opt/zitadel/config.yaml
  systemctl restart -q zitadel
  msg_ok "Zitadel restarted with ExternalDomain set to current IP"

  msg_info "Create zitadel-rerun.sh"
  cat << EOF > ~/zitadel-rerun.sh
systemctl stop zitadel
timeout --kill-after=5s 15s zitadel setup --masterkeyFile /opt/zitadel/.masterkey --config /opt/zitadel/config.yaml
systemctl restart zitadel
EOF
  msg_ok "Bash script for rerunning Zitadel after changing Zitadel config.yaml"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8080/ui/console${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/zitadel.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "zitadel" "zitadel/zitadel"; then
    msg_info "Stopping Service"
    systemctl stop zitadel
    msg_ok "Stopped Service"

    rm -f /usr/local/bin/zitadel
    fetch_and_deploy_gh_release "zitadel" "zitadel/zitadel" "prebuild" "latest" "/usr/local/bin" "zitadel-linux-$(get_system_arch).tar.gz"

    msg_info "Updating Zitadel"
    $STD zitadel setup --masterkeyFile /opt/zitadel/.masterkey --config /opt/zitadel/config.yaml --init-projections=true
    msg_ok "Updated Zitadel"

    msg_info "Starting Service"
    systemctl start zitadel
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
