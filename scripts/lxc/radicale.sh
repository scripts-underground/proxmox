#!/usr/bin/env bash
# shellcheck disable=SC2034
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://radicale.org/ | Github: https://github.com/Kozea/Radicale

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Radicale"
var_tags="${var_tags:-calendar}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y apache2-utils
  msg_ok "Installed Dependencies"

  PYTHON_VERSION="3.13" setup_uv
  fetch_and_deploy_gh_release "Radicale" "Kozea/Radicale" "tarball" "latest" "/opt/radicale"

  msg_info "Setting up Radicale"
  cd /opt/radicale || exit
  RNDPASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  $STD htpasswd -c -b -5 /opt/radicale/users admin "$RNDPASS"
  cat << EOF > ~/radicale.creds
Radicale Credentials
Admin User: admin
Admin Password: $RNDPASS
EOF

  mkdir -p /etc/radicale
  cat << EOF > /etc/radicale/config
[server]
hosts = 0.0.0.0:5232

[auth]
type = htpasswd
htpasswd_filename = /opt/radicale/users
htpasswd_encryption = sha512

[storage]
type = multifilesystem
filesystem_folder = /var/lib/radicale/collections

[web]
type = internal
EOF
  msg_ok "Set up Radicale"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/radicale.service
[Unit]
Description=A simple CalDAV (calendar) and CardDAV (contact) server
After=network.target
Requires=network.target

[Service]
WorkingDirectory=/opt/radicale
ExecStart=/usr/local/bin/uv run -m radicale --config /etc/radicale/config
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now radicale
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:5232${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/radicale ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "Radicale" "Kozea/Radicale"; then
    msg_info "Stopping Service"
    systemctl stop radicale
    msg_ok "Stopped Service"

    msg_info "Backing up Users File"
    cp /opt/radicale/users /opt/radicale_users_backup
    msg_ok "Backed up Users File"

    PYTHON_VERSION="3.13" setup_uv
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "Radicale" "Kozea/Radicale" "tarball" "latest" "/opt/radicale"

    msg_info "Restoring Users File"
    rm -f /opt/radicale/users
    mv /opt/radicale_users_backup /opt/radicale/users
    msg_ok "Restored Users File"

    if grep -q 'start.sh' /etc/systemd/system/radicale.service; then
      sed -i -e '/^Description/i[Unit]' \
        -e '\|^ExecStart|iWorkingDirectory=/opt/radicale' \
        -e 's|^ExecStart=.*|ExecStart=/usr/local/bin/uv run -m radicale --config /etc/radicale/config|' /etc/systemd/system/radicale.service
      systemctl daemon-reload
    fi
    if [[ ! -f /etc/radicale/config ]]; then
      msg_info "Migrating to Config File (/etc/radicale/config)"
      mkdir -p /etc/radicale
      cat << EOF > /etc/radicale/config
[server]
hosts = 0.0.0.0:5232

[auth]
type = htpasswd
htpasswd_filename = /opt/radicale/users
htpasswd_encryption = sha512

[storage]
type = multifilesystem
filesystem_folder = /var/lib/radicale/collections

[web]
type = internal
EOF
      msg_ok "Migrated to Config (/etc/radicale/config)"
    fi
    msg_info "Starting Service"
    systemctl start radicale
    msg_ok "Started Service"
    msg_ok "Updated Successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
