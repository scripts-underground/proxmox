#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://docs.jellyseerr.dev/ | Github: https://github.com/Fallenbagel/jellyseerr

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Jellyseerr"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    python3-setuptools
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "jellyseerr" "Fallenbagel/jellyseerr" "tarball"
  pnpm_desired=$(grep -Po '"pnpm":\s*"\K[^"]+' /opt/jellyseerr/package.json)
  NODE_VERSION="22" NODE_MODULE="pnpm@$pnpm_desired" setup_nodejs

  msg_info "Installing Jellyseerr (Patience)"
  export CYPRESS_INSTALL_BINARY=0
  cd /opt/jellyseerr || exit
  $STD pnpm install --frozen-lockfile
  export NODE_OPTIONS="--max-old-space-size=3072"
  $STD pnpm build
  mkdir -p /etc/jellyseerr/
  cat << EOF > /etc/jellyseerr/jellyseerr.conf
## Jellyseerr's default port is 5055, if you want to use both, change this.
## specify on which port to listen
PORT=5055

## specify on which interface to listen, by default Jellyseerr listens on all interfaces
HOST=0.0.0.0

## Uncomment if you want to force Node.js to resolve IPv4 before IPv6 (advanced users only)
# FORCE_IPV4_FIRST=true
EOF
  msg_ok "Installed Jellyseerr"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/jellyseerr.service
[Unit]
Description=jellyseerr Service
After=network.target

[Service]
EnvironmentFile=/etc/jellyseerr/jellyseerr.conf
Environment=NODE_ENV=production
Type=exec
WorkingDirectory=/opt/jellyseerr
ExecStart=/usr/bin/node dist/index.js

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now jellyseerr
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:5055${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/jellyseerr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if [[ -f "/opt/jellyseerr/package.json" ]] && [[ "$(grep -m1 '"version"' /opt/jellyseerr/package.json | awk -F'"' '{print $4}')" == "2.7.3" ]]; then
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Jellyseerr v2.7.3 detected."
    echo
    echo "Seerr is the new unified Jellyseerr and Overseerr."
    echo "More info: https://docs.seerr.dev/blog/seerr-release"
    echo
    read -rp "Do you want to migrate to Seerr now? (y/N): " MIGRATE
    echo
    if [[ ! "$MIGRATE" =~ ^[Yy]$ ]]; then
      msg_info "Migration cancelled. Exiting."
      exit 0
    fi

    msg_info "Switching update script to Seerr"
    TMP_UPDATE=$(mktemp)
    cat << 'EOF' > "$TMP_UPDATE"
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/seerr.sh)"
EOF
    mv "$TMP_UPDATE" /usr/bin/update
    chmod +x /usr/bin/update
    msg_ok "Switched update script to Seerr"
    msg_warn "Please type 'update' again to complete the migration"
    exit 0
  fi

  msg_info "Updating Jellyseerr"
  cd /opt/jellyseerr || exit
  systemctl stop jellyseerr
  output=$(git pull --no-rebase)
  pnpm_desired=$(grep -Po '"pnpm":\s*"\K[^"]+' /opt/jellyseerr/package.json)
  NODE_VERSION="22" NODE_MODULE="pnpm@$pnpm_desired" setup_nodejs
  if echo "$output" | grep -q "Already up to date."; then
    msg_ok "$APP is already up to date."
    exit
  fi
  rm -rf dist .next node_modules
  export CYPRESS_INSTALL_BINARY=0
  cd /opt/jellyseerr || exit
  $STD pnpm install --frozen-lockfile
  export NODE_OPTIONS="--max-old-space-size=3072"
  $STD pnpm build
  cat << EOF > /etc/systemd/system/jellyseerr.service
[Unit]
Description=jellyseerr Service
After=network.target

[Service]
EnvironmentFile=/etc/jellyseerr/jellyseerr.conf
Environment=NODE_ENV=production
Type=exec
WorkingDirectory=/opt/jellyseerr
ExecStart=/usr/bin/node dist/index.js

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl start jellyseerr
  msg_ok "Updated Jellyseerr"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
