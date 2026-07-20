#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2155
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://gethomepage.dev/
APP="Homepage"
var_tags="${var_tags:-dashboard}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y jq
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" NODE_MODULE="pnpm@latest" setup_nodejs

  RELEASE=$(get_latest_github_release "gethomepage/homepage")
  fetch_and_deploy_gh_release "homepage" "gethomepage/homepage" "tarball"

  msg_info "Installing Homepage (Patience)"
  mkdir -p /opt/homepage/config
  cd /opt/homepage || exit
  cp /opt/homepage/src/skeleton/* /opt/homepage/config
  echo 'onlyBuiltDependencies=*' >> .npmrc
  $STD pnpm install
  export NEXT_PUBLIC_VERSION="v$RELEASE"
  export NEXT_PUBLIC_REVISION="source"
  export NEXT_PUBLIC_BUILDTIME=$(curl -fsSL https://api.github.com/repos/gethomepage/homepage/releases/latest | jq -r '.published_at')
  export NEXT_TELEMETRY_DISABLED=1
  $STD pnpm build
  LOCAL_IP=$(hostname -I | awk '{print $1}')
  echo "HOMEPAGE_ALLOWED_HOSTS=localhost:3000,${LOCAL_IP}:3000" > /opt/homepage/.env
  msg_ok "Installed Homepage"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/homepage.service
[Unit]
Description=Homepage
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
WorkingDirectory=/opt/homepage/
ExecStart=pnpm start

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now homepage
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/homepage ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="22" NODE_MODULE="pnpm@latest" setup_nodejs
  ensure_dependencies jq

  if check_for_gh_release "homepage" "gethomepage/homepage"; then
    msg_info "Stopping service"
    systemctl stop homepage
    msg_ok "Stopped service"

    msg_info "Creating Backup"
    cp /opt/homepage/.env /opt/homepage.env
    cp -r /opt/homepage/config /opt/homepage_config_backup
    [[ -d /opt/homepage/public/images ]] && cp -r /opt/homepage/public/images /opt/homepage_images_backup
    [[ -d /opt/homepage/public/icons ]] && cp -r /opt/homepage/public/icons /opt/homepage_icons_backup
    msg_ok "Created Backup"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "homepage" "gethomepage/homepage" "tarball"

    msg_info "Restoring Backup"
    mv /opt/homepage.env /opt/homepage
    rm -rf /opt/homepage/config
    mv /opt/homepage_config_backup /opt/homepage/config
    msg_ok "Restored Backup"

    msg_info "Updating Homepage (Patience)"
    RELEASE=$(get_latest_github_release "gethomepage/homepage")
    cd /opt/homepage || exit
    echo 'onlyBuiltDependencies=*' >> .npmrc
    $STD pnpm install
    $STD pnpm update --no-save caniuse-lite
    export NEXT_PUBLIC_VERSION="v$RELEASE"
    export NEXT_PUBLIC_REVISION="source"
    export NEXT_PUBLIC_BUILDTIME=$(curl -fsSL https://api.github.com/repos/gethomepage/homepage/releases/latest | jq -r '.published_at')
    export NEXT_TELEMETRY_DISABLED=1
    $STD pnpm build
    [[ -d /opt/homepage_images_backup ]] && mv /opt/homepage_images_backup /opt/homepage/public/images
    [[ -d /opt/homepage_icons_backup ]] && mv /opt/homepage_icons_backup /opt/homepage/public/icons
    msg_ok "Updated Homepage"

    msg_info "Starting service"
    systemctl start homepage
    msg_ok "Started service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
