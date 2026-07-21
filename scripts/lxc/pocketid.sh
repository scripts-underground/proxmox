#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Snarkenfaugister
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/pocket-id/pocket-id

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="PocketID"
var_tags="${var_tags:-identity-provider}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  read -r -p "${TAB3}What public URL do you want to use (e.g. pocketid.mydomain.com)? " public_url
  fetch_and_deploy_gh_release "pocket-id" "pocket-id/pocket-id" "singlefile" "latest" "/opt/pocket-id/" "pocket-id_linux_$(get_system_arch)"

  msg_info "Configuring Pocket ID"
  ENCRYPTION_KEY=$(openssl rand -base64 32)

  cat << EOF > /opt/pocket-id/.env
APP_ENV=production
APP_URL=https://${public_url}
TRUST_PROXY=false
# MAXMIND_LICENSE_KEY=
PORT=1411
HOST=0.0.0.0
ENCRYPTION_KEY=${ENCRYPTION_KEY}
EOF
  msg_ok "Configured Pocket ID"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/pocketid.service
[Unit]
Description=Pocket ID Service
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/pocket-id
EnvironmentFile=/opt/pocket-id/.env
ExecStart=/opt/pocket-id/pocket-id
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  msg_ok "Created Service"

  msg_info "Starting Service"
  systemctl enable -q --now pocketid
  msg_ok "Started Services"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Configure your reverse proxy to point to:${BGN} ${IP}:1411${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}https://{PUBLIC_URL}/setup${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/pocket-id ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  ENCRYPTION_KEY=$(openssl rand -base64 32)
  if ! grep -q '^ENCRYPTION_KEY=' /opt/pocket-id/.env; then
    echo "ENCRYPTION_KEY=$ENCRYPTION_KEY" >> /opt/pocket-id/.env
  fi

  if check_for_gh_release "pocket-id" "pocket-id/pocket-id"; then
    if [ "$(printf '%s\n%s' "$(cat ~/.pocket-id 2> /dev/null || echo 0.0.0)" "1.0.0" | sort -V | head -n1)" = "$(cat ~/.pocket-id 2> /dev/null || echo 0.0.0)" ] &&
      [ "$(cat ~/.pocket-id 2> /dev/null || echo 0.0.0)" != "1.0.0" ]; then
      msg_info "Migrating ${APP}"
      systemctl -q disable --now pocketid-backend pocketid-frontend caddy
      mv /etc/caddy/Caddyfile ~/Caddyfile.bak
      $STD apt remove --purge caddy nodejs -y
      $STD apt autoremove -y
      rm /etc/apt/{keyrings/nodesource.gpg,sources.list.d/nodesource.list}
      rm -r /usr/local/go
      cp -r /opt/pocket-id/backend/data /opt/data
      cp /opt/pocket-id/backend/.env /opt/env
      sed -i -e 's/PUBLIC_//g' \
        -e '/^SQLITE_DB_PATH/d' \
        -e '/^POSTGRES/s/^/# /' \
        -e '/^UPLOAD_PATH/d' \
        -e 's/8080/1411/' /opt/env
      rm -r /opt/pocket-id
      rm /etc/systemd/system/pocketid-frontend.service
      BACKEND="/etc/systemd/system/pocketid-backend.service"
      sed -i -e 's/Backend/Service/' \
        -e 's/\/backend\|-backend//g' "$BACKEND"
      mv "$BACKEND" ${BACKEND//-backend/}
      systemctl daemon-reload
      systemctl -q enable pocketid
      mkdir /opt/pocket-id
      mv /opt/data /opt/pocket-id
      msg_ok "Migration complete. The reverse proxy port has been changed to 1411."
    else
      msg_info "Stopping Service"
      systemctl stop pocketid
      msg_ok "Stopped Service"
      cp /opt/pocket-id/.env /opt/env
    fi

    fetch_and_deploy_gh_release "pocket-id" "pocket-id/pocket-id" "singlefile" "latest" "/opt/pocket-id/" "pocket-id_linux_$(get_system_arch)"
    mv /opt/env /opt/pocket-id/.env

    msg_info "Starting Service"
    systemctl start pocketid
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
