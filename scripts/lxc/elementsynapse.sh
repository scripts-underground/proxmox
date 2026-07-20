#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tremor021
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/element-hq/synapse

# shellcheck disable=SC2034
APP="Element Synapse"
var_tags="${var_tags:-server;matrix}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    apt-transport-https \
    debconf-utils
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs

  msg_info "Setting up Matrix repository"
  setup_deb822_repo "matrix-org" \
    "https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg" \
    "https://packages.matrix.org/debian/" \
    "$(get_os_info codename)" \
    "main"
  msg_ok "Set up Matrix repository"

  local servername
  servername=$(hostname -f)
  servername=$(prompt_input_required "Enter your Matrix server name (cannot be changed later):" "$servername" 120 "var_servername")

  msg_info "Installing Element Synapse"
  echo "matrix-synapse-py3 matrix-synapse/server-name string $servername" | debconf-set-selections
  echo "matrix-synapse-py3 matrix-synapse/report-stats boolean false" | debconf-set-selections
  echo "exit 101" > /usr/sbin/policy-rc.d
  chmod +x /usr/sbin/policy-rc.d
  $STD apt install -y matrix-synapse-py3
  rm -f /usr/sbin/policy-rc.d
  sed -i 's/127.0.0.1/0.0.0.0/g' /etc/matrix-synapse/homeserver.yaml
  sed -i "s/'::1', //g" /etc/matrix-synapse/homeserver.yaml
  local secret
  secret=$(openssl rand -hex 32)
  local admin_pass
  admin_pass="$(openssl rand -base64 18 | cut -c1-13)"
  echo "enable_registration_without_verification: true" >> /etc/matrix-synapse/homeserver.yaml
  echo "registration_shared_secret: ${secret}" >> /etc/matrix-synapse/homeserver.yaml
  cat << EOF >> /etc/matrix-synapse/homeserver.yaml

# MatrixRTC / Element Call configuration
experimental_features:
  msc3266_enabled: true
  msc4222_enabled: true

max_event_delay_duration: 24h

rc_message:
  per_second: 0.5
  burst_count: 30

rc_delayed_event_mgmt:
  per_second: 1
  burst_count: 20
EOF
  systemctl enable -q --now matrix-synapse
  $STD register_new_matrix_user -a --user admin --password "$admin_pass" --config /etc/matrix-synapse/homeserver.yaml
  cat << EOF > ~/matrix.creds
Matrix-Credentials
Admin username: admin
Admin password: $admin_pass
EOF
  systemctl stop matrix-synapse
  sed -i '34d' /etc/matrix-synapse/homeserver.yaml
  systemctl start matrix-synapse
  msg_ok "Installed Element Synapse"

  fetch_and_deploy_gh_release "synapse-admin" "etkecc/synapse-admin" "tarball"

  msg_info "Installing Synapse-Admin"
  cd /opt/synapse-admin || exit
  $STD yarn global add serve
  $STD yarn install --ignore-engines
  $STD yarn build
  mv ./dist ../ && rm -rf * && mv ../dist ./
  msg_ok "Installed Synapse-Admin"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/synapse-admin.service
[Unit]
Description=Synapse-Admin Service
After=network.target
Requires=matrix-synapse.service

[Service]
Type=simple
WorkingDirectory=/opt/synapse-admin
ExecStart=/usr/local/bin/serve -s dist -l 5173
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now synapse-admin
  msg_ok "Created Service"

  msg_ok "Credentials saved to ~/matrix.creds"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access Matrix Synapse using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8008${CL}"
  echo -e "${INFO}${YW} Access Synapse-Admin using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5173${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /etc/matrix-synapse ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs
  msg_info "Updating LXC"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated LXC"
  if check_for_gh_release "synapse-admin" "etkecc/synapse-admin"; then
    msg_info "Stopping Service"
    systemctl stop synapse-admin
    msg_ok "Stopped Service"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "synapse-admin" "etkecc/synapse-admin" "tarball" "latest" "/opt/synapse-admin"
    msg_info "Building Synapse-Admin"
    cd /opt/synapse-admin || exit
    $STD yarn global add serve
    $STD yarn install --ignore-engines
    $STD yarn build
    mv ./dist ../ && rm -rf * && mv ../dist ./
    msg_ok "Built Synapse-Admin"
    msg_info "Starting Service"
    systemctl start synapse-admin
    msg_ok "Started Service"
    msg_ok "Updated Synapse-Admin to ${CHECK_UPDATE_RELEASE}"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
