#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Michel Roegl-Brunner (michelroegl-brunner)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://cosmos-cloud.io/

# shellcheck disable=SC2034
APP="Cosmos"
var_tags="${var_tags:-cloud;docker}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_fuse="${var_fuse:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y ca-certificates openssl snapraid avahi-daemon fdisk mergerfs unzip
  setup_docker
  msg_ok "Installed Dependencies"
  fetch_and_deploy_gh_release "cosmos" "azukaar/Cosmos-Server" "prebuild" "latest" "/opt/cosmos" "cosmos-cloud-*-$(get_system_arch).zip"
  chmod +x /opt/cosmos/cosmos
  cat << 'EOF' > /opt/cosmos/start.sh
#!/usr/bin/env bash
exec /opt/cosmos/cosmos "$@"
EOF
  chmod +x /opt/cosmos/start.sh
  mkdir -p /etc/sysconfig
  touch /etc/sysconfig/CosmosCloud
  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/cosmos.service
[Unit]
Description=Cosmos Cloud service
After=network.target
ConditionFileIsExecutable=/opt/cosmos/start.sh
StartLimitInterval=10
StartLimitBurst=5
[Service]
Type=simple
ExecStart=/opt/cosmos/start.sh
WorkingDirectory=/opt/cosmos
Restart=always
RestartSec=2
EnvironmentFile=-/etc/sysconfig/CosmosCloud
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now cosmos
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/cosmos ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "${APP} updates itself automatically via its built-in update mechanism."
  msg_ok "No manual update needed."
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
