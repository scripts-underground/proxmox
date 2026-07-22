#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Dunky13
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/cmintey/wishlist

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Wishlist"
var_tags="${var_tags:-sharing}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    openssl \
    caddy
  msg_ok "Installed Dependencies"

  msg_info "Setting up Node.js"
  NODE_VERSION="24" NODE_MODULE="pnpm@11" setup_nodejs
  msg_ok "Set up Node.js"

  fetch_and_deploy_gh_release "wishlist" "cmintey/wishlist" "tarball"
  LATEST_APP_VERSION=$(get_latest_github_release "cmintey/wishlist")

  msg_info "Installing Wishlist"
  cd /opt/wishlist || exit
  cp .env.example .env
  sed -i "s|^ORIGIN=.*|ORIGIN=http://${LOCAL_IP}:3280|" /opt/wishlist/.env
  echo "" >> /opt/wishlist/.env
  echo "NODE_ENV=production" >> /opt/wishlist/.env
  $STD pnpm install --frozen-lockfile
  $STD pnpm svelte-kit sync
  $STD pnpm prisma generate
  while IFS= read -r -d '' f; do
    sed -i 's|/usr/src/app/|/opt/wishlist/|g' "$f"
  done < <(grep -rlZ '/usr/src/app/' /opt/wishlist)
  export VERSION="v${LATEST_APP_VERSION}"
  # shellcheck disable=SC2155
  export SHA="v${LATEST_APP_VERSION}"
  $STD pnpm run build
  $STD pnpm prune --prod
  chmod +x /opt/wishlist/entrypoint.sh
  mkdir -p /opt/wishlist/uploads
  mkdir -p /opt/wishlist/data
  msg_ok "Installed Wishlist"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/wishlist.service
[Unit]
Description=Wishlist Service
After=network.target

[Service]
WorkingDirectory=/opt/wishlist
EnvironmentFile=/opt/wishlist/.env
ExecStart=/usr/bin/env sh -c './entrypoint.sh'
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now wishlist
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3280${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/wishlist ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "wishlist" "cmintey/wishlist"; then
    msg_info "Setting up Node.js"
    NODE_VERSION="24" NODE_MODULE="pnpm@11" setup_nodejs
    msg_ok "Set up Node.js"

    msg_info "Stopping Service"
    systemctl stop wishlist
    msg_ok "Stopped Service"

    create_backup /opt/wishlist/.env /opt/wishlist/uploads /opt/wishlist/data

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "wishlist" "cmintey/wishlist" "tarball"
    LATEST_APP_VERSION=$(get_latest_github_release "cmintey/wishlist")

    restore_backup

    msg_info "Updating Wishlist"
    cd /opt/wishlist || exit
    $STD pnpm install --frozen-lockfile
    $STD pnpm svelte-kit sync
    $STD pnpm prisma generate
    while IFS= read -r -d '' f; do
      sed -i 's|/usr/src/app/|/opt/wishlist/|g' "$f"
    done < <(grep -rlZ '/usr/src/app/' /opt/wishlist)
    export VERSION="v${LATEST_APP_VERSION}"
    # shellcheck disable=SC2155
    export SHA="v${LATEST_APP_VERSION}"
    $STD pnpm run build
    $STD pnpm prune --prod
    chmod +x /opt/wishlist/entrypoint.sh
    msg_ok "Updated Wishlist"

    msg_info "Starting Service"
    systemctl start wishlist
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
