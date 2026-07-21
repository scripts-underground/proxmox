#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: vhsdream
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/fccview/rwMarkable

# shellcheck disable=SC2034
APP="rwMarkable"
var_tags="${var_tags:-tasks;notes}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-3072}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs
  fetch_and_deploy_gh_release "rwMarkable" "fccview/rwMarkable" "tarball" "latest" "/opt/rwmarkable"

  msg_info "Installing ${APP}"
  cd /opt/rwmarkable || exit
  $STD yarn --frozen-lockfile
  $STD yarn next telemetry disable
  $STD yarn build
  mkdir -p data/{users,checklists,notes}

  cat << 'ENVEOF' > /opt/rwmarkable/.env
NODE_ENV=production
# HTTPS=true

# --- SSO with OIDC (optional)
# SSO_MODE=oidc
# OIDC_ISSUER=<your-oidc-issuer-url>
# OIDC_CLIENT_ID=<oidc-client-id>
# APP_URL=<https://app.domain.tld>
# SSO_FALLBACK_LOCAL=true
# OIDC_CLIENT_SECRET=your_client_secret
# OIDC_ADMIN_GROUPS=admins
ENVEOF
  msg_ok "Installed ${APP}"

  msg_info "Creating Service"
  cat << 'SERVICEEOF' > /etc/systemd/system/rwmarkable.service
[Unit]
Description=rwMarkable Server
After=network.target

[Service]
WorkingDirectory=/opt/rwmarkable
EnvironmentFile=/opt/rwmarkable/.env
ExecStart=yarn start
Restart=on-abnormal

[Install]
WantedBy=multi-user.target
SERVICEEOF
  systemctl enable -q --now rwmarkable
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/rwmarkable ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping service"
  systemctl -q disable --now rwmarkable
  msg_ok "Stopped Service"

  NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs
  CLEAN_INSTALL=1 fetch_and_deploy_gh_release "jotty" "fccview/jotty" "tarball" "latest" "/opt/jotty"

  msg_info "Updating app"
  cd /opt/jotty || exit
  $STD yarn --frozen-lockfile
  $STD yarn next telemetry disable
  $STD yarn build
  msg_ok "Updated app"

  msg_info "Migrating configuration & data"
  cp /opt/rwmarkable/.env /opt/jotty/.env
  mkdir -p /opt/jotty/data
  cp -r /opt/rwmarkable/data/* /opt/jotty/data 2> /dev/null || true
  cp -r /opt/rwmarkable/config/* /opt/jotty/config 2> /dev/null || true
  msg_ok "Migrated configuration & data"

  msg_info "Patching systemd service file"
  sed -i 's/rw[M|m]arkable/jotty/g' /etc/systemd/system/rwmarkable.service
  mv /etc/systemd/system/rwmarkable.service /etc/systemd/system/jotty.service
  systemctl daemon-reload
  msg_ok "Patched systemd service file"

  msg_info "Patching update script"
  sed -i 's/rwmarkable/jotty/g' /usr/bin/update
  msg_ok "Patched update script"

  msg_info "Starting jotty service"
  systemctl -q enable --now jotty
  msg_ok "Started jotty service"
  msg_ok "Migrated Successfully!"
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
