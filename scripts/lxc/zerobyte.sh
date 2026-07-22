#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/nicotsx/zerobyte

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Zerobyte"
var_tags="${var_tags:-backup;encryption;restic}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-6144}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  echo "davfs2 davfs2/suid_file boolean false" | debconf-set-selections
  $STD apt install -y \
    bzip2 \
    fuse3 \
    git \
    sshfs \
    davfs2 \
    openssh-client
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "restic" "restic/restic" "singlefile" "latest" "/usr/local/bin" "restic_*_linux_$(get_system_arch).bz2"
  mv /usr/local/bin/restic /usr/local/bin/restic.bz2
  bzip2 -d /usr/local/bin/restic.bz2
  chmod +x /usr/local/bin/restic

  fetch_and_deploy_gh_release "rclone" "rclone/rclone" "prebuild" "latest" "/opt/rclone" "rclone-*-linux-$(get_system_arch).zip"
  ln -sf /opt/rclone/rclone /usr/local/bin/rclone

  SHOUTRRR_ARCH="$(get_system_arch)"
  [[ "$SHOUTRRR_ARCH" == "arm64" ]] && SHOUTRRR_ARCH="arm64v8"
  fetch_and_deploy_gh_release "shoutrrr" "nicholas-fedor/shoutrrr" "prebuild" "latest" "/opt/shoutrrr" "shoutrrr_linux_${SHOUTRRR_ARCH}_*.tar.gz"
  ln -sf /opt/shoutrrr/shoutrrr /usr/local/bin/shoutrrr

  msg_info "Installing Bun"
  export BUN_INSTALL="/root/.bun"
  curl -fsSL https://bun.sh/install | $STD bash
  ln -sf /root/.bun/bin/bun /usr/local/bin/bun
  ln -sf /root/.bun/bin/bunx /usr/local/bin/bunx
  msg_ok "Installed Bun"

  NODE_VERSION="24" setup_nodejs
  fetch_and_deploy_gh_release "zerobyte" "nicotsx/zerobyte" "tarball"

  msg_info "Building Zerobyte (Patience)"
  cd /opt/zerobyte || exit
  export VITE_RESTIC_VERSION
  VITE_RESTIC_VERSION=$(cat ~/.restic)
  export VITE_RCLONE_VERSION
  VITE_RCLONE_VERSION=$(cat ~/.rclone)
  export VITE_SHOUTRRR_VERSION
  VITE_SHOUTRRR_VERSION=$(cat ~/.shoutrrr)
  export NODE_OPTIONS="--max-old-space-size=3072"
  $STD bun install
  $STD node ./node_modules/vite/bin/vite.js build
  msg_ok "Built Zerobyte"

  msg_info "Configuring Zerobyte"
  mkdir -p /var/lib/zerobyte/{data,restic/cache,repositories,volumes}
  APP_SECRET=$(openssl rand -hex 32)
  cat << EOF > /opt/zerobyte/.env
BASE_URL=http://${LOCAL_IP}:4096
APP_SECRET=${APP_SECRET}
PORT=4096
ZEROBYTE_DATABASE_URL=/var/lib/zerobyte/data/zerobyte.db
RESTIC_CACHE_DIR=/var/lib/zerobyte/restic/cache
ZEROBYTE_REPOSITORIES_DIR=/var/lib/zerobyte/repositories
ZEROBYTE_VOLUMES_DIR=/var/lib/zerobyte/volumes
MIGRATIONS_PATH=/opt/zerobyte/app/drizzle
NODE_ENV=production
EOF
  msg_ok "Configured Zerobyte"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/zerobyte.service
[Unit]
Description=Zerobyte Backup Automation
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/zerobyte
EnvironmentFile=/opt/zerobyte/.env
ExecStart=/usr/local/bin/bun .output/server/index.mjs
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now zerobyte
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:4096${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/zerobyte ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "zerobyte" "nicotsx/zerobyte"; then
    msg_info "Stopping Service"
    systemctl stop zerobyte
    msg_ok "Stopped Service"

    create_backup /opt/zerobyte/.env

    ensure_dependencies git
    NODE_VERSION="24" setup_nodejs
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "zerobyte" "nicotsx/zerobyte" "tarball"

    restore_backup

    msg_info "Building Zerobyte"
    export NODE_OPTIONS="--max-old-space-size=3072"
    cd /opt/zerobyte || exit
    $STD bun install
    $STD node ./node_modules/vite/bin/vite.js build
    msg_ok "Built Zerobyte"

    msg_info "Starting Service"
    systemctl start zerobyte
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
