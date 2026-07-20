#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: vhsdream
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/iv-org/invidious

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Invidious"
var_tags="${var_tags:-streaming}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    git \
    pkg-config \
    libssl-dev \
    libxml2-dev \
    libyaml-dev \
    libgmp-dev \
    libreadline-dev \
    librsvg2-bin \
    libsqlite3-dev \
    zlib1g-dev \
    libpcre2-dev \
    libevent-dev \
    fonts-open-sans
  msg_ok "Installed Dependencies"

  if [[ "$(get_system_arch)" == "amd64" ]]; then
    setup_deb822_repo "crystal" "https://download.opensuse.org/repositories/devel:/languages:/crystal/Debian_13/Release.key" "https://download.opensuse.org/repositories/devel:/languages:/crystal/Debian_13/" "./"
    $STD apt install -y crystal
  else
    fetch_and_deploy_gh_release "Crystal" "crystal-lang/crystal" "prebuild" "latest" "/opt/crystal" "crystal-*-linux-aarch64-bundled.tar.gz"
    ln -sf /opt/crystal/bin/crystal /usr/local/bin/crystal
    ln -sf /opt/crystal/bin/shards /usr/local/bin/shards
  fi

  PG_VERSION="17" setup_postgresql
  PG_DB_NAME="invidious" PG_DB_USER="invidious" setup_postgresql_db
  fetch_and_deploy_gh_release "Invidious" "iv-org/invidious" "tarball" "latest" "/opt/invidious"
  COMPANION_ARCH="$(uname -m)"
  fetch_and_deploy_gh_release "Invidious Companion" "iv-org/invidious-companion" "prebuild" "latest" "/opt/invidious-companion" "invidious_companion-${COMPANION_ARCH}-unknown-linux-gnu.tar.gz"

  msg_info "Building Invidious"
  cd /opt/invidious || exit
  INVIDIOUS_VERSION="$(cat ~/.invidious 2> /dev/null || echo "unknown")"
  INVIDIOUS_VERSION="${INVIDIOUS_VERSION#v}"
  sed -i \
    -e "s~^\(\s*CURRENT_BRANCH\s*=\).*~\1 \"master\"~" \
    -e "s~^\(\s*CURRENT_COMMIT\s*=\).*~\1 \"\"~" \
    -e "s~^\(\s*CURRENT_VERSION\s*=\).*~\1 \"${INVIDIOUS_VERSION}\"~" \
    -e "s~^\(\s*CURRENT_TAG\s*=\).*~\1 \"${INVIDIOUS_VERSION}\"~" \
    -e "s~^\(\s*ASSET_COMMIT\s*=\).*~\1 \"\"~" \
    src/invidious.cr
  $STD make
  msg_ok "Built Invidious"

  msg_info "Configuring Invidious"
  SECRET_KEY="$(openssl rand -hex 8)"
  HMAC_KEY="$(openssl rand -hex 32)"
  sed -e '\~^db:~,\~dbname:~d' \
    -e "s~^#database_.*~database_url: postgres://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}~" \
    -e 's~^#check_tables.*~check_tables: true~' \
    -e 's~^#invidious_companion:~invidious_companion:~' \
    -e 's~^#  - private_~  - private_~' \
    -e "s~^#invidious_companion_key:.*~invidious_companion_key: \"${SECRET_KEY}\"~" \
    -e "s~^hmac_key:.*~hmac_key: \"${HMAC_KEY}\"~" \
    /opt/invidious/config/config.example.yml > /opt/invidious/config/config.yml
  chmod 600 /opt/invidious/config/config.yml

  cat << EOF > /etc/logrotate.d/invidious.logrotate
/opt/invidious/invidious.log {
  rotate 4
  weekly
  notifempty
  missingok
  compress
  minsize 1048576
}
EOF
  chmod 0644 /etc/logrotate.d/invidious.logrotate
  msg_ok "Configured Invidious"

  msg_info "Migrating database"
  $STD ./invidious --migrate
  msg_ok "Migrated database"

  msg_info "Configuring services"
  sed -e 's|^User=invidious|User=root|' \
    -e 's|^Group=invidious|Group=root|' \
    -e 's|/home/invidious/invidious|/opt/invidious|g' \
    /opt/invidious/invidious.service > /etc/systemd/system/invidious.service
  mkdir -p /var/tmp/youtubei.js
  cat << EOF > /etc/systemd/system/invidious-companion.service
[Unit]
Description=Invidious Companion
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/invidious-companion
Environment=SERVER_SECRET_KEY=${SECRET_KEY}
Environment=CACHE_DIRECTORY=/var/tmp/youtubei.js
ExecStart=/opt/invidious-companion/invidious_companion
Restart=always
RestartSec=2s

[Install]
WantedBy=multi-user.target
EOF
  systemctl -q enable --now invidious invidious-companion
  msg_ok "Configured services"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/invidious ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "Invidious" "iv-org/invidious"; then
    msg_info "Stopping services"
    $STD systemctl stop invidious-companion invidious
    msg_ok "Stopped services"

    create_backup /opt/invidious/config/config.yml

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "Invidious" "iv-org/invidious" "tarball" "latest" "/opt/invidious"
    if check_for_gh_release "Invidious-Companion" "iv-org/invidious-companion"; then
      COMPANION_ARCH="$(uname -m)"
      CLEAN_INSTALL=1 fetch_and_deploy_gh_release "Invidious-Companion" "iv-org/invidious-companion" "prebuild" "latest" "/opt/invidious-companion" "invidious_companion-${COMPANION_ARCH}-unknown-linux-gnu.tar.gz"
    fi

    msg_info "Rebuilding Invidious"
    cd /opt/invidious || exit
    INVIDIOUS_VERSION="$(cat ~/.invidious 2> /dev/null || echo "unknown")"
    INVIDIOUS_VERSION="${INVIDIOUS_VERSION#v}"
    sed -i \
      -e "s~^\(\s*CURRENT_BRANCH\s*=\).*~\1 \"master\"~" \
      -e "s~^\(\s*CURRENT_COMMIT\s*=\).*~\1 \"\"~" \
      -e "s~^\(\s*CURRENT_VERSION\s*=\).*~\1 \"${INVIDIOUS_VERSION}\"~" \
      -e "s~^\(\s*CURRENT_TAG\s*=\).*~\1 \"${INVIDIOUS_VERSION}\"~" \
      -e "s~^\(\s*ASSET_COMMIT\s*=\).*~\1 \"\"~" \
      src/invidious.cr
    $STD make
    msg_ok "Rebuilt Invidious"

    restore_backup

    msg_info "Starting services"
    $STD systemctl start invidious invidious-companion
    msg_ok "Started services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
