#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/hedgedoc/hedgedoc

# shellcheck disable=SC2034
APP="HedgeDoc"
var_tags="${var_tags:-collaboration;markdown}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_git_repo="${var_lxc_git_repo:-hedgedoc/hedgedoc}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git curl
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" setup_nodejs

  msg_info "Installing HedgeDoc"
  fetch_and_deploy_gh_release "hedgedoc" "$var_lxc_git_repo" "tarball" "latest" "/opt/hedgedoc"
  cd /opt/hedgedoc || exit
  $STD npm install --omit=dev
  mkdir -p /opt/hedgedoc/data
  cat << EOF > /opt/hedgedoc/.env
NEXT_PUBLIC_USE_MOCK_API=false
HD_DATABASE_URL=sqlite:///opt/hedgedoc/data/database.sqlite
EOF
  $STD npx prisma db push --accept-data-loss
  msg_ok "Installed HedgeDoc"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/hedgedoc.service
[Unit]
Description=HedgeDoc
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/hedgedoc
Environment=NEXT_PUBLIC_USE_MOCK_API=false
Environment=HD_DATABASE_URL=sqlite:///opt/hedgedoc/data/database.sqlite
ExecStart=/opt/hedgedoc/node_modules/.bin/next start -p 80
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now hedgedoc
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

  if [[ ! -d /opt/hedgedoc ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "hedgedoc" "$var_lxc_git_repo"; then
    msg_info "Updating ${APP}"
    systemctl stop hedgedoc
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "hedgedoc" "$var_lxc_git_repo" "tarball" "latest" "/opt/hedgedoc"
    cd /opt/hedgedoc || exit
    $STD npm install --omit=dev
    $STD npx prisma db push --accept-data-loss
    systemctl start hedgedoc
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
