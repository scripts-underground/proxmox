#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/louislam/uptime-kuma

# shellcheck disable=SC2034
APP="Uptime Kuma"
var_tags="${var_tags:-monitoring;uptime}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_git_repo="${var_lxc_git_repo:-louislam/uptime-kuma}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git curl
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" setup_nodejs

  msg_info "Installing Uptime Kuma"
  clone_and_deploy_gh_commit "uptime-kuma" "$var_lxc_git_repo" "master" "" "" /opt/uptime-kuma
  cd /opt/uptime-kuma || exit
  $STD npm ci --omit=dev
  $STD npm run build
  msg_ok "Installed Uptime Kuma"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/uptime-kuma.service
[Unit]
Description=Uptime Kuma
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/uptime-kuma
ExecStart=/usr/bin/node /opt/uptime-kuma/server/server.js --port 80
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now uptime-kuma
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  render_header
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/uptime-kuma ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  cd /opt/uptime-kuma || exit
  if $STD git fetch origin master && ! git diff --quiet origin/master; then
    msg_info "Updating ${APP}"
    systemctl stop uptime-kuma
    $STD git pull origin master
    $STD npm ci --omit=dev
    $STD npm run build
    systemctl start uptime-kuma
    msg_ok "Updated successfully!"
  else
    msg_ok "${APP} is up to date"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
